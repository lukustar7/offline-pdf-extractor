import SwiftUI
import PDFKit
import Vision

// MARK: - 支持的去水印与正文场景模式
enum WatermarkRemovalMode: String, CaseIterable, Identifiable, Codable {
    case auto = "智能诊断匹配（推荐）"
    case modeA = "纯文本过滤（文字版 PDF 专用）"
    case modeB = "物理遮罩 + OCR（正文扫描件 + 文字水印）"
    case modeC = "OCR + 智能过滤（纯扫描件水印）"
    
    var id: String { self.rawValue }
}

// MARK: - 支持的文字提取模式
enum ExtractionMode: String, CaseIterable, Identifiable, Codable {
    case smart = "智能提取（推荐）"
    case textOnly = "仅提取活字（极速）"
    case ocrOnly = "强制全部 OCR（适合扫描件）"
    
    var id: String { self.rawValue }
}

// MARK: - 面向用户的三类 PDF 处理场景
enum PDFProcessingScenario: String, CaseIterable, Identifiable, Codable {
    case electronicTextWithTextWatermark = "electronicTextWithTextWatermark"
    case scannedTextWithTextWatermark = "scannedTextWithTextWatermark"
    case fullyScanned = "fullyScanned"
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "电子文本 + 电子水印"
        case .scannedTextWithTextWatermark:
            return "扫描正文 + 电子水印"
        case .fullyScanned:
            return "全扫描件"
        }
    }
    
    var subtitle: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "正文和水印都可选中，直接清理文本层。"
        case .scannedTextWithTextWatermark:
            return "正文是图片，水印是后加文本，先 OCR 后过滤。"
        case .fullyScanned:
            return "正文和水印都在图像里，整页 OCR 后过滤残留。"
        }
    }
    
    var extractionMode: ExtractionMode {
        switch self {
        case .electronicTextWithTextWatermark:
            return .textOnly
        case .scannedTextWithTextWatermark, .fullyScanned:
            return .ocrOnly
        }
    }
    
    var watermarkRemovalMode: WatermarkRemovalMode {
        switch self {
        case .electronicTextWithTextWatermark:
            return .modeA
        case .scannedTextWithTextWatermark:
            return .modeB
        case .fullyScanned:
            return .modeC
        }
    }
    
    var enableWatermarkFilter: Bool {
        true
    }
    
    var maskTextWatermarkBeforeOCR: Bool {
        false
    }
    
    var statusDescription: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "读取 PDF 文本层，删除已确认的电子水印词，不重新 OCR。"
        case .scannedTextWithTextWatermark:
            return "保留原始扫描图像执行 Vision OCR，再按电子水印词过滤残留；必要时才手动开启遮罩。"
        case .fullyScanned:
            return "对整页图像执行 OCR，再按水印词过滤文本；重叠严重时建议继续使用 AI 净化。"
        }
    }
}

// MARK: - 核心 PDF 处理与 OCR 引擎
@MainActor
class PDFExtractorEngine: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var currentStatus: String = "未加载文件"
    @Published var logOutput: String = ""
    @Published var pdfFileName: String = ""
    @Published var pdfFileSize: String = ""
    @Published var pdfTotalPages: Int = 0
    @Published var isAnalyzingWatermarks = false
    @Published var watermarkCandidates: [WatermarkCandidate] = []
    
    // 物理页码对应的提取文本缓存，支持四栏工作区翻页同步联动
    @Published var extractedPagesText: [Int: String] = [:]
    
    // 预计剩余时间 (ETA)
    @Published var etaString: String = ""
    
    // 供主线程 UI PDFPreviewView 渲染的 PDFKit Document
    @Published var pdfDocument: PDFDocument?
    var pdfURL: URL?
    
    struct WatermarkCandidate: Identifiable, Hashable, Sendable {
        let id = UUID()
        let text: String
        let occurrenceCount: Int
        var isSelected: Bool = true
    }
    
    private struct PageExtractionOutput: Sendable {
        let text: String
        let warning: String?
    }
    
    private struct OCRExtractionOutput: Sendable {
        let text: String
        let warning: String?
    }
    
    // 线程安全的中止控制标志与锁
    private let cancelLock = NSLock()
    private var rawIsCancelled = false
    var isCancelledSafe: Bool {
        get {
            cancelLock.lock()
            defer { cancelLock.unlock() }
            return rawIsCancelled
        }
        set {
            cancelLock.lock()
            rawIsCancelled = newValue
            cancelLock.unlock()
            self.isCancelled = newValue
        }
    }
    @Published var isCancelled = false
    
    // 用于追踪文字提取任务唯一性的 Token，防止旧线程并发干扰
    private let tokenLock = NSLock()
    private var _currentExtractToken: UUID?
    var currentExtractTokenSafe: UUID? {
        get {
            tokenLock.lock()
            defer { tokenLock.unlock() }
            return _currentExtractToken
        }
        set {
            tokenLock.lock()
            _currentExtractToken = newValue
            tokenLock.unlock()
        }
    }
    
    // 用于追踪加载任务的 Token，防止连续加载文件时的时序竞争（线程安全）
    private let loadTokenLock = NSLock()
    private var _currentLoadToken: UUID?
    private var currentLoadTokenSafe: UUID? {
        get {
            loadTokenLock.lock()
            defer { loadTokenLock.unlock() }
            return _currentLoadToken
        }
        set {
            loadTokenLock.lock()
            _currentLoadToken = newValue
            loadTokenLock.unlock()
        }
    }
    
    // 常用 OCR 易错错字本地校对字典
    private let ocrCorrectionMap: [String: String] = [
        "面且": "而且",
        "我门": "我们",
        "系境": "系统",
        "支特": "支持",
        "功育": "功能",
        "用广": "用户",
        "设量": "设置",
        "提取码": "提取",
        "温道": "通道",
        "相回": "相同"
    ]
    
    init() {}
    
    // 用于通知 UI 展示加载、导出或 OCR 过程中的可见错误信息。
    @Published var errorMessage: String? = nil
    
    /// 异步非阻塞加载 PDF，避免大文件实例化导致 UI 卡顿
    func loadPDF(url: URL) {
        self.errorMessage = nil
        self.pdfURL = url
        self.pdfFileName = url.lastPathComponent
        
        // 计算文件大小
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useKB]
            formatter.countStyle = .file
            self.pdfFileSize = formatter.string(fromByteCount: size)
        } else {
            self.pdfFileSize = "未知大小"
        }
        
        let token = UUID()
        self.currentLoadTokenSafe = token
        
        self.isAnalyzingWatermarks = true
        self.currentStatus = "正在加载文件..."
        self.logOutput = "正在加载文件: \(url.lastPathComponent)\n"
        
        // 使用 Task 派发后台线程加载 PDFDocument 实例，彻底解放主线程
        Task {
            let (doc, pageCount) = await self.performPDFLoadingInBackground(url: url)
            
            // 确保没有被更新的加载任务覆盖
            guard self.currentLoadTokenSafe == token else { return }
            
            guard let resolvedDoc = doc else {
                self.pdfDocument = nil
                self.pdfFileName = ""
                self.pdfFileSize = ""
                self.pdfTotalPages = 0
                self.isAnalyzingWatermarks = false
                self.currentStatus = "加载 PDF 失败"
                self.logOutput += "错误: 无法解析或加载该 PDF 文件。\n"
                self.errorMessage = "无法解析或加载此 PDF 文件。该文件可能已损坏、被加密或格式不正确。"
                return
            }
            
            self.pdfDocument = resolvedDoc
            self.pdfTotalPages = pageCount
            self.logOutput += "文件成功加载: \(url.lastPathComponent)\n"
            self.currentStatus = "就绪，正在自动分析水印词..."
            
            // 自动分析水印词（后台非阻塞）
            await self.analyzeWatermarksInQueue(url: url, token: token)
        }
    }
    
    /// 后台非阻塞加载 PDFDocument 实例
    nonisolated private func performPDFLoadingInBackground(url: URL) async -> (PDFDocument?, Int) {
        let doc = PDFDocument(url: url)
        return (doc, doc?.pageCount ?? 0)
    }
    
    /// 清除当前加载的文件并强行中断正在运行的后台任务
    func clear() {
        cancelPDFExtraction()
        self.currentLoadTokenSafe = nil
        self.currentExtractTokenSafe = nil
        
        self.isAnalyzingWatermarks = false
        self.pdfDocument = nil
        self.pdfURL = nil
        self.pdfFileName = ""
        self.pdfFileSize = ""
        self.pdfTotalPages = 0
        self.watermarkCandidates = []
        self.progress = 0.0
        self.etaString = ""
        self.isProcessing = false
        self.isCancelledSafe = false
        self.currentStatus = "未加载文件"
        self.logOutput = ""
        self.extractedPagesText = [:]
    }
    
    /// 后台非阻塞执行前 30 页水印字词词频计算
    private func analyzeWatermarksInQueue(url: URL, token: UUID) async {
        self.isAnalyzingWatermarks = true
        
        let candidates = await Task.detached(priority: .userInitiated) { () -> [WatermarkCandidate] in
            guard let doc = PDFDocument(url: url) else { return [] }
            
            var counts: [String: Int] = [:]
            let pageCount = doc.pageCount
            let maxPagesToScan = min(pageCount, 30)
            
            for i in 0..<maxPagesToScan {
                guard let page = doc.page(at: i) else { continue }
                let selections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
                for sel in selections {
                    if let text = sel.string?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !text.isEmpty {
                        if text.count >= 2 && text.count <= 30 {
                            if counts.count < 5000 || counts[text] != nil {
                                counts[text, default: 0] += 1
                            }
                        }
                    }
                }
            }
            
            let threshold = max(2, Int(Double(maxPagesToScan) * 0.2))
            let filtered = counts.filter { $0.value >= threshold }
                .map { WatermarkCandidate(text: $0.key, occurrenceCount: $0.value, isSelected: true) }
                .sorted { $0.occurrenceCount > $1.occurrenceCount }
            return filtered
        }.value
        
        guard self.currentLoadTokenSafe == token else { return }
        
        self.watermarkCandidates = candidates
        self.isAnalyzingWatermarks = false
        if candidates.isEmpty {
            self.currentStatus = "分析完毕，未检测到高频活字水印。"
            self.logOutput += "未检测到明显的页面重复活字水印，您也可以手动添加过滤词。\n"
        } else {
            self.currentStatus = "分析完毕，发现 \(candidates.count) 个疑似水印词。"
            self.logOutput += "检测到疑似水印词：\n" + candidates.map { " - \"\($0.text)\" (\($0.occurrenceCount)页出现)" }.joined(separator: "\n") + "\n"
        }
    }
    
    /// 解析页码范围输入字符串，返回需要处理的 1-indexed 页码列表 (支持中英文多种连接符)
    func parsePageRange(_ rangeStr: String, maxPages: Int) -> [Int] {
        let trimmed = rangeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Array(1...maxPages)
        }
        
        var pages = Set<Int>()
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ",，"))
        let connectors = CharacterSet(charactersIn: "-~～—")
        
        for part in parts {
            let cleanPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if cleanPart.rangeOfCharacter(from: connectors) != nil {
                let rangeParts = cleanPart.components(separatedBy: connectors)
                if rangeParts.count == 2,
                   let start = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)),
                   let end = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)) {
                    let rangeStart = max(1, min(start, maxPages))
                    let rangeEnd = max(1, min(end, maxPages))
                    let actualStart = min(rangeStart, rangeEnd)
                    let actualEnd = max(rangeStart, rangeEnd)
                    for p in actualStart...actualEnd {
                        pages.insert(p)
                    }
                }
            } else if let p = Int(cleanPart) {
                if p >= 1 && p <= maxPages {
                    pages.insert(p)
                }
            }
        }
        return pages.isEmpty ? Array(1...maxPages) : pages.sorted()
    }
    
    /// 执行文字提取与去水印任务 (现代 async 改造)
    func extractText(
        scenario: PDFProcessingScenario,
        activeWatermarks: Set<String>,
        customWatermarks: String,
        ignoreCase: Bool,
        mode: ExtractionMode,
        watermarkRemovalMode: WatermarkRemovalMode,
        enableWatermarkFilter: Bool,
        eraseImageWatermark: Bool,
        pageRangeString: String,
        completion: @escaping (String, URL?, URL?, Double) -> Void
    ) {
        guard let url = pdfURL else { return }
        guard !isProcessing else { return }
        
        let token = UUID()
        self.currentExtractTokenSafe = token
        
        isProcessing = true
        isCancelledSafe = false
        progress = 0.0
        etaString = "" 
        currentStatus = "准备开始处理..."
        logOutput += "\n=== 开始执行文字提取与去水印 ===\n"
        
        self.extractedPagesText = [:]
        
        // 解析自定义水印词
        let customList = customWatermarks
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let allWatermarkFilters = activeWatermarks.union(customList)
        if enableWatermarkFilter {
            logOutput += "生效的水印过滤词: \(allWatermarkFilters.sorted().joined(separator: ", "))\n"
        } else {
            logOutput += "水印识别与过滤已关闭，将保留原始提取结果。\n"
        }
        logOutput += "PDF 处理场景: \(scenario.title)\n"
        logOutput += "处理管线: \(scenario.statusDescription)\n"
        logOutput += "正文提取通道: \(mode.rawValue)\n"
        logOutput += "去水印工作模式: \(watermarkRemovalMode.rawValue)\n"
        if scenario == .scannedTextWithTextWatermark {
            logOutput += "OCR 前电子水印遮罩: \(eraseImageWatermark ? "开启" : "关闭")\n"
        }
        
        let targetPages = parsePageRange(pageRangeString, maxPages: pdfTotalPages)
        logOutput += "计划提取页码: \(targetPages.map { String($0) }.joined(separator: ", ")) (共 \(targetPages.count) 页)\n"
        
        let startTime = Date()
        
        // 在异步协程链中接力执行
        Task {
            // 异步后台加载 PDFDocument 实例副本，杜绝多线程冲突
            let (loadedDoc, _) = await self.performPDFLoadingInBackground(url: url)
            guard let doc = loadedDoc else {
                self.updateStatus("错误：无法在后台读取 PDF 文档。")
                self.errorMessage = "无法读取当前 PDF 文档。该文件可能已损坏、被加密或正在被其他程序占用。"
                self.isProcessing = false
                return
            }
            
            var memoryBuffer = ""
            let totalToProcess = targetPages.count
            
            for (index, pageIndex) in targetPages.enumerated() {
                // 安全校验与中断控制
                guard self.currentExtractTokenSafe == token else { return }
                if self.isCancelledSafe {
                    self.updateStatus("处理已中止。")
                    self.isProcessing = false
                    completion(memoryBuffer, nil, nil, 0.0)
                    return
                }
                
                self.updateStatus("正在处理第 \(pageIndex) 页 (总进度: \(index + 1) / \(totalToProcess))...")
                
                // 协程挂起，在非隔离后台执行单页提取逻辑（包含图片渲染、物理白底遮挡与 Vision OCR）
                let pageOutput = await self.performPageExtractionInBackground(
                    doc: doc,
                    pageIndex: pageIndex,
                    watermarkFilters: allWatermarkFilters,
                    ignoreCase: ignoreCase,
                    mode: mode,
                    watermarkRemovalMode: watermarkRemovalMode,
                    enableWatermarkFilter: enableWatermarkFilter,
                    eraseImageWatermark: eraseImageWatermark
                )
                let pageText = pageOutput.text
                
                guard self.currentExtractTokenSafe == token else { return }
                
                if let warning = pageOutput.warning {
                    self.errorMessage = warning
                    self.updateStatus("警告：\(warning)")
                }
                
                // 将页面结果写入缓存，触发 SwiftUI UI 刷新
                self.extractedPagesText[pageIndex] = pageText
                
                let pageHeader = "\n[第 \(pageIndex) 页]\n"
                let pageContent = pageText + "\n"
                memoryBuffer += pageHeader + pageContent
                
                // 更新进度与 ETA 估值
                self.updateProgress(Double(index + 1) / Double(totalToProcess))
                let elapsed = Date().timeIntervalSince(startTime)
                let avgTime = elapsed / Double(index + 1)
                let remainingPages = totalToProcess - (index + 1)
                let etaSeconds = avgTime * Double(remainingPages)
                
                let etaText: String
                if remainingPages == 0 {
                    etaText = "即将完成"
                } else if etaSeconds < 60 {
                    etaText = "预计约剩 \(Int(etaSeconds)) 秒"
                } else {
                    let minutes = Int(etaSeconds) / 60
                    let seconds = Int(etaSeconds) % 60
                    etaText = "预计约剩 \(minutes) 分 \(seconds) 秒"
                }
                self.etaString = etaText
            }
            
            guard self.currentExtractTokenSafe == token else { return }
            
            let totalTime = Date().timeIntervalSince(startTime)
            let avgPageTime = totalToProcess > 0 ? totalTime / Double(totalToProcess) : 0.0
            
            self.updateStatus("处理完成，平均每页耗时 \(String(format: "%.2f", avgPageTime)) 秒。")
            self.isProcessing = false
            self.etaString = ""
            completion(memoryBuffer, nil, nil, avgPageTime)
        }
    }
    
    /// 后台非主线程执行页面处理核心计算（解耦 MainActor）
    nonisolated private func performPageExtractionInBackground(
        doc: PDFDocument,
        pageIndex: Int,
        watermarkFilters: Set<String>,
        ignoreCase: Bool,
        mode: ExtractionMode,
        watermarkRemovalMode: WatermarkRemovalMode,
        enableWatermarkFilter: Bool,
        eraseImageWatermark: Bool
    ) async -> PageExtractionOutput {
        await Task.detached(priority: .userInitiated) { [weak self] () async -> PageExtractionOutput in
            guard let self = self else {
                return PageExtractionOutput(text: "", warning: "页面处理任务已释放，未能完成本页识别。")
            }
            
            guard let page = doc.page(at: pageIndex - 1) else {
                return PageExtractionOutput(text: "", warning: "第 \(pageIndex) 页不存在或无法读取。")
            }
            let pageOutput = await self.processPage(
                page: page,
                pageIndex: pageIndex,
                watermarkFilters: watermarkFilters,
                ignoreCase: ignoreCase,
                mode: mode,
                watermarkRemovalMode: watermarkRemovalMode,
                enableWatermarkFilter: enableWatermarkFilter,
                eraseImageWatermark: eraseImageWatermark
            )
            
            let correctedText = self.applyLocalCorrection(pageOutput.text)
            return PageExtractionOutput(text: correctedText, warning: pageOutput.warning)
        }.value
    }
    
    /// 主动中止当前的文字提取线程
    func cancelPDFExtraction() {
        if isProcessing {
            isCancelledSafe = true
            currentStatus = "正在强行中止任务..."
            logOutput += "\n[提取提示] 正在接收用户中止提取的指令...\n"
        }
    }
    
    private func updateStatus(_ status: String) {
        self.currentStatus = status
        self.logOutput += status + "\n"
        if self.logOutput.count > 50000 {
            let lines = self.logOutput.components(separatedBy: "\n")
            if lines.count > 200 {
                self.logOutput = "...(旧日志已截断)...\n" + lines.suffix(200).joined(separator: "\n")
            }
        }
    }
    
    private func updateProgress(_ val: Double) {
        self.progress = val
    }
    
    /// 常用 OCR 纠错本地替换
    nonisolated private func applyLocalCorrection(_ text: String) -> String {
        var corrected = text
        for (wrong, right) in ocrCorrectionMap {
            corrected = corrected.replacingOccurrences(of: wrong, with: right)
        }
        return corrected
    }
    
    /// 底层同步分流纯计算方法 (已解耦 MainActor，专职后台运行)
    nonisolated private func processPage(
        page: PDFPage,
        pageIndex: Int,
        watermarkFilters: Set<String>,
        ignoreCase: Bool,
        mode: ExtractionMode,
        watermarkRemovalMode: WatermarkRemovalMode,
        enableWatermarkFilter: Bool,
        eraseImageWatermark: Bool
    ) async -> PageExtractionOutput {
        let allSelections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
        let activeFilters = enableWatermarkFilter ? watermarkFilters : Set<String>()
        
        var resolvedMode = watermarkRemovalMode
        if resolvedMode == .auto {
            let rawCharCount = allSelections.reduce(0) { $0 + ($1.string?.count ?? 0) }
            if rawCharCount > 100 {
                resolvedMode = .modeA
            } else {
                resolvedMode = (rawCharCount > 0) ? .modeB : .modeC
            }
        }
        
        let shouldOCR: Bool
        switch mode {
        case .smart:
            shouldOCR = (resolvedMode == .modeC) || (resolvedMode == .modeB)
        case .textOnly:
            shouldOCR = false
        case .ocrOnly:
            shouldOCR = true
        }
        
        var pageResult = ""
        
        if shouldOCR {
            var maskSelections: [PDFSelection] = []
            if resolvedMode == .modeB && enableWatermarkFilter {
                for sel in allSelections {
                    guard let text = sel.string else { continue }
                    if isWatermark(text: text, filters: activeFilters, ignoreCase: ignoreCase) {
                        maskSelections.append(sel)
                    }
                }
            }
            
            let coverSelections = (resolvedMode == .modeB && eraseImageWatermark) ? maskSelections : []
            
            if let cgImage = renderPageToCGImage(page: page, watermarkSelections: coverSelections) {
                let ocrOutput = await performLocalOCR(on: cgImage)
                let rawOCRText = ocrOutput.text
                if enableWatermarkFilter {
                    pageResult = self.cleanText(rawOCRText, filters: activeFilters, ignoreCase: ignoreCase)
                } else {
                    pageResult = rawOCRText
                }
                
                if let warning = ocrOutput.warning {
                    return PageExtractionOutput(text: pageResult, warning: "第 \(pageIndex) 页 OCR 失败：\(warning)")
                }
            } else {
                return PageExtractionOutput(text: "", warning: "第 \(pageIndex) 页无法渲染为图像，OCR 已跳过。")
            }
        } else {
            // 文字提取模式
            var normalTextPieces: [String] = []
            var lastWasEmpty = false
            
            for sel in allSelections {
                guard let text = sel.string else { continue }
                if enableWatermarkFilter && isWatermarkStrict(text: text, filters: activeFilters, ignoreCase: ignoreCase) {
                    continue
                }
                
                let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if !lastWasEmpty {
                        normalTextPieces.append("")
                        lastWasEmpty = true
                    }
                } else {
                    normalTextPieces.append(text)
                    lastWasEmpty = false
                }
            }
            pageResult = normalTextPieces.joined(separator: "\n")
        }
        
        return PageExtractionOutput(text: pageResult, warning: nil)
    }
    
    /// 水印包含比对
    nonisolated private func isWatermark(text: String, filters: Set<String>, ignoreCase: Bool) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.isEmpty { return false }
        
        let textToCompare = ignoreCase ? cleanText.lowercased() : cleanText
        for filter in filters {
            let filterToCompare = ignoreCase ? filter.lowercased() : filter
            if textToCompare.contains(filterToCompare) {
                return true
            }
        }
        return false
    }
    
    /// 水印严格完全匹配
    nonisolated private func isWatermarkStrict(text: String, filters: Set<String>, ignoreCase: Bool) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.isEmpty { return false }
        
        let textToCompare = ignoreCase ? cleanText.lowercased() : cleanText
        for filter in filters {
            let filterToCompare = ignoreCase ? filter.lowercased() : filter
            if textToCompare == filterToCompare {
                return true
            }
        }
        return false
    }
    
    /// 水印文本净化
    nonisolated private func cleanText(_ text: String, filters: Set<String>, ignoreCase: Bool) -> String {
        var cleaned = text
        for filter in filters {
            if filter.count >= 2 {
                if ignoreCase {
                    cleaned = replaceIgnoreCase(in: cleaned, target: filter, with: "")
                } else {
                    cleaned = cleaned.replacingOccurrences(of: filter, with: "")
                }
            }
        }
        
        let rawLines = cleaned.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        var lastLineWasEmpty = false
        
        for line in rawLines {
            let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                if !lastLineWasEmpty {
                    cleanedLines.append("")
                    lastLineWasEmpty = true
                }
            } else {
                cleanedLines.append(line)
                lastLineWasEmpty = false
            }
        }
        
        return cleanedLines.joined(separator: "\n")
    }
    
    nonisolated private func replaceIgnoreCase(in text: String, target: String, with replacement: String) -> String {
        var result = text
        while let range = result.range(of: target, options: .caseInsensitive) {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
    
    /// 高阶物理渲染
    nonisolated private func renderPageToCGImage(page: PDFPage, watermarkSelections: [PDFSelection]) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let maxPixelDimension: CGFloat = 4096.0
        let maxPageDimension = max(pageBounds.width, pageBounds.height)
        let scale: CGFloat = min(3.0, maxPixelDimension / maxPageDimension)
        let width = pageBounds.width * scale
        let height = pageBounds.height * scale
        
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: Int(height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor.white.set()
        rect.fill()
        
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        
        page.draw(with: .mediaBox, to: context.cgContext)
        
        NSColor.white.set()
        for selection in watermarkSelections {
            let bounds = selection.bounds(for: page)
            let coverRect = bounds.insetBy(dx: -1.5, dy: -1.5)
            coverRect.fill()
        }
        
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
    
    /// 本地 Vision OCR 识别算法 (使用 Continuation 异步协程挂起平替 Semaphore 物理阻塞)
    nonisolated private func performLocalOCR(on cgImage: CGImage) async -> OCRExtractionOutput {
        await withCheckedContinuation { continuation in
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNRecognizeTextRequest { (request, error) in
                if let error {
                    continuation.resume(returning: OCRExtractionOutput(text: "", warning: error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRExtractionOutput(text: "", warning: "Vision 未返回可解析的文本结果。"))
                    return
                }
                
                var recognizedText = ""
                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        recognizedText += candidate.string + "\n"
                    }
                }
                continuation.resume(returning: OCRExtractionOutput(text: recognizedText, warning: nil))
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            
            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(returning: OCRExtractionOutput(text: "", warning: error.localizedDescription))
            }
        }
    }
}
