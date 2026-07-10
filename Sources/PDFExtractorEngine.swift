import SwiftUI
@preconcurrency import PDFKit

// MARK: - 核心 PDF 状态引擎

/// 只负责管理界面可观察状态与任务生命周期。
/// PDFKit 渲染、文字过滤和 Vision OCR 均由 `PDFExtractionWorker` 在后台串行执行。
@MainActor
final class PDFExtractorEngine: ObservableObject {
    @Published var isProcessing = false
    @Published var progress = 0.0
    @Published var currentStatus = "未加载文件"
    @Published var logOutput = ""
    @Published var pdfFileName = ""
    @Published var pdfFileSize = ""
    @Published var pdfTotalPages = 0
    @Published var isAnalyzingWatermarks = false
    @Published var watermarkCandidates: [WatermarkCandidate] = []
    @Published var extractedPagesText: [Int: String] = [:]
    @Published var etaString = ""
    @Published var pdfDocument: PDFDocument?
    @Published var errorMessage: String?

    private(set) var pdfURL: URL?

    /// 疑似水印需要用户确认，因此保留可变的勾选状态。
    struct WatermarkCandidate: Identifiable, Hashable, Sendable {
        let id = UUID()
        let text: String
        let occurrenceCount: Int
        // 词频分析无法区分水印与重复页眉，默认不勾选，必须由用户明确确认。
        var isSelected = false
    }

    private var loadTask: Task<Void, Never>?
    private var extractionTask: Task<Void, Never>?
    private var currentLoadToken: UUID?
    private var currentExtractionToken: UUID?

    // MARK: 文件加载

    /// 加载并验证 PDF，随后在后台分析最多 30 页高频文本。
    func loadPDF(url: URL) {
        cancelPDFExtraction(showStatus: false)
        loadTask?.cancel()

        let token = UUID()
        currentLoadToken = token
        prepareForLoading(url: url)

        loadTask = Task { [weak self] in
            let result = await PDFDocumentLoader.load(url: url)
            guard let self,
                  !Task.isCancelled,
                  self.currentLoadToken == token else { return }

            guard let result else {
                self.applyLoadFailure("无法解析此 PDF。文件可能已损坏、格式不正确或无法访问。")
                return
            }
            guard !result.isLocked else {
                self.applyLoadFailure("此 PDF 已加密并处于锁定状态，请先在其他工具中解锁后再导入。")
                return
            }
            guard result.pageCount > 0 else {
                self.applyLoadFailure("此 PDF 不包含可读取的页面。")
                return
            }

            // 后台创建完成后，PDFDocument 只交给主线程 PDFView 使用，不再返回后台工作器。
            self.pdfDocument = result.document
            self.pdfTotalPages = result.pageCount
            self.currentStatus = "就绪，正在自动分析水印词..."
            self.appendLog("文件成功加载：\(url.lastPathComponent)")

            let detectedCandidates = await PDFDocumentLoader.detectWatermarks(url: url)
            guard !Task.isCancelled,
                  self.currentLoadToken == token else { return }

            self.watermarkCandidates = detectedCandidates.map {
                WatermarkCandidate(text: $0.text, occurrenceCount: $0.occurrenceCount)
            }
            self.isAnalyzingWatermarks = false
            self.currentLoadToken = nil
            self.loadTask = nil

            if detectedCandidates.isEmpty {
                self.currentStatus = "分析完毕，未检测到高频电子水印词。"
                self.appendLog("未检测到明显的页面重复电子水印词，可按需手动添加过滤词。")
            } else {
                self.currentStatus = "分析完毕，发现 \(detectedCandidates.count) 个疑似水印词。"
                let details = detectedCandidates
                    .map { " - \"\($0.text)\"（\($0.occurrenceCount) 页出现）" }
                    .joined(separator: "\n")
                self.appendLog("检测到疑似水印词：\n\(details)")
            }
        }
    }

    /// 清除当前文件，并让所有旧任务的结果立即失效。
    func clear() {
        loadTask?.cancel()
        loadTask = nil
        currentLoadToken = nil
        cancelPDFExtraction(showStatus: false)

        isAnalyzingWatermarks = false
        pdfDocument = nil
        pdfURL = nil
        pdfFileName = ""
        pdfFileSize = ""
        pdfTotalPages = 0
        watermarkCandidates = []
        progress = 0
        etaString = ""
        currentStatus = "未加载文件"
        logOutput = ""
        extractedPagesText = [:]
        errorMessage = nil
    }

    // MARK: 文字提取

    /// 启动一次不可变的提取请求。每页结果直接写入页码缓存，不再额外保存整篇文本副本。
    func extractText(request: PDFExtractionRequest) {
        guard let url = pdfURL, pdfDocument != nil else {
            errorMessage = "请先导入可读取的 PDF 文件。"
            return
        }
        guard !isProcessing else { return }
        guard !isAnalyzingWatermarks else {
            errorMessage = "水印词仍在分析中，请等待分析完成后再开始提取。"
            return
        }
        guard !request.targetPages.isEmpty,
              request.targetPages.allSatisfy({ $0 >= 1 && $0 <= pdfTotalPages }) else {
            errorMessage = "提取页码不在当前 PDF 的有效范围内。"
            return
        }

        let token = UUID()
        currentExtractionToken = token
        isProcessing = true
        progress = 0
        etaString = ""
        currentStatus = "准备开始处理..."
        extractedPagesText = [:]
        errorMessage = nil

        appendLog("\n=== 开始执行文字提取与去水印 ===")
        appendLog("PDF 处理场景：\(request.scenario.title)")
        appendLog("处理管线：\(request.scenario.statusDescription)")
        appendLog("正文提取通道：\(request.scenario.extractionMode.rawValue)")
        appendLog("去水印工作模式：\(request.scenario.watermarkRemovalMode.rawValue)")
        appendLog("生效的水印过滤词数量：\(request.watermarkFilters.count)")
        if request.scenario == .scannedTextWithTextWatermark {
            appendLog("OCR 前电子水印遮罩：\(request.eraseImageWatermark ? "开启" : "关闭")")
        }
        appendLog("计划提取 \(request.targetPages.count) 页：\(summarizedPages(request.targetPages))")

        extractionTask = Task { [weak self] in
            guard let worker = await PDFExtractionWorker.make(url: url),
                  let self,
                  !Task.isCancelled,
                  self.currentExtractionToken == token else {
                if let self, self.currentExtractionToken == token {
                    self.finishExtractionWithFailure("无法创建 PDF 后台处理器。")
                }
                return
            }

            let startTime = Date()
            let totalPageCount = request.targetPages.count

            for (offset, pageNumber) in request.targetPages.enumerated() {
                guard !Task.isCancelled,
                      self.currentExtractionToken == token else { return }

                self.updateStatus("正在处理第 \(pageNumber) 页（\(offset + 1) / \(totalPageCount)）...")
                let pageOutput = await worker.extractPage(
                    pageNumber: pageNumber,
                    request: request
                )

                guard !Task.isCancelled,
                      self.currentExtractionToken == token else { return }

                self.extractedPagesText[pageNumber] = pageOutput.text
                if let warning = pageOutput.warning {
                    self.errorMessage = warning
                    self.appendLog("警告：\(warning)")
                }

                self.updateProgress(
                    completedPageCount: offset + 1,
                    totalPageCount: totalPageCount,
                    startTime: startTime
                )
            }

            guard !Task.isCancelled,
                  self.currentExtractionToken == token else { return }

            let totalTime = Date().timeIntervalSince(startTime)
            let averagePageTime = totalTime / Double(totalPageCount)
            self.updateStatus("处理完成，平均每页耗时 \(String(format: "%.2f", averagePageTime)) 秒。")
            self.isProcessing = false
            self.etaString = ""
            self.currentExtractionToken = nil
            self.extractionTask = nil
        }
    }

    /// 取消任务后立即冻结旧任务写入；正在执行的单页 Vision 调用结束后会被直接丢弃。
    func cancelPDFExtraction(showStatus: Bool = true) {
        guard isProcessing || extractionTask != nil else { return }

        currentExtractionToken = nil
        extractionTask?.cancel()
        extractionTask = nil
        isProcessing = false
        etaString = ""

        if showStatus {
            currentStatus = "已取消文字提取。"
            appendLog("[提取提示] 用户已取消文字提取，未完成页面不会写入结果。")
        }
    }

    // MARK: 私有状态辅助

    private func prepareForLoading(url: URL) {
        errorMessage = nil
        pdfDocument = nil
        pdfURL = url
        pdfFileName = url.lastPathComponent
        pdfTotalPages = 0
        watermarkCandidates = []
        extractedPagesText = [:]
        progress = 0
        etaString = ""
        isAnalyzingWatermarks = true
        currentStatus = "正在加载文件..."
        logOutput = "正在加载文件：\(url.lastPathComponent)\n"

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useKB]
            formatter.countStyle = .file
            pdfFileSize = formatter.string(fromByteCount: size)
        } else {
            pdfFileSize = "未知大小"
        }
    }

    private func applyLoadFailure(_ message: String) {
        pdfDocument = nil
        pdfURL = nil
        pdfFileName = ""
        pdfFileSize = ""
        pdfTotalPages = 0
        isAnalyzingWatermarks = false
        currentStatus = "加载 PDF 失败"
        errorMessage = message
        appendLog("错误：\(message)")
        currentLoadToken = nil
        loadTask = nil
    }

    private func finishExtractionWithFailure(_ message: String) {
        updateStatus("错误：\(message)")
        errorMessage = message
        isProcessing = false
        etaString = ""
        currentExtractionToken = nil
        extractionTask = nil
    }

    private func updateProgress(
        completedPageCount: Int,
        totalPageCount: Int,
        startTime: Date
    ) {
        progress = Double(completedPageCount) / Double(totalPageCount)
        let remainingPageCount = totalPageCount - completedPageCount
        guard remainingPageCount > 0 else {
            etaString = "即将完成"
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let averagePageTime = elapsed / Double(completedPageCount)
        let remainingSeconds = max(0, Int(averagePageTime * Double(remainingPageCount)))
        if remainingSeconds < 60 {
            etaString = "预计约剩 \(remainingSeconds) 秒"
        } else {
            etaString = "预计约剩 \(remainingSeconds / 60) 分 \(remainingSeconds % 60) 秒"
        }
    }

    private func updateStatus(_ status: String) {
        currentStatus = status
        appendLog(status)
    }

    private func appendLog(_ message: String) {
        logOutput += message + "\n"
        guard logOutput.count > 50_000 else { return }

        let lines = logOutput.components(separatedBy: .newlines)
        if lines.count > 200 {
            logOutput = "...(旧日志已截断)...\n" + lines.suffix(200).joined(separator: "\n")
        }
    }

    private func summarizedPages(_ pages: [Int]) -> String {
        guard pages.count > 20 else {
            return pages.map(String.init).joined(separator: ", ")
        }
        let prefix = pages.prefix(10).map(String.init).joined(separator: ", ")
        let suffix = pages.suffix(3).map(String.init).joined(separator: ", ")
        return "\(prefix), ... , \(suffix)"
    }
}
