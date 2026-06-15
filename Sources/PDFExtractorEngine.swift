import SwiftUI
import PDFKit
import Vision

// MARK: - 核心 PDF 处理与 OCR 引擎
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
    
    // 预计剩余时间 (ETA)
    @Published var etaString: String = ""
    
    // 供主线程 UI PDFPreviewView 渲染的 PDFKit Document
    @Published var pdfDocument: PDFDocument?
    var pdfURL: URL?
    
    struct WatermarkCandidate: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let occurrenceCount: Int
        var isSelected: Bool = true
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
            DispatchQueue.main.async { [weak self] in
                self?.isCancelled = newValue
            }
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
    
    // 用于追踪加载任务的 Token，防止连续加载文件时的时序竞争
    private var currentLoadToken: UUID?
    
    // 串行 PDF 提取专用队列，彻底将所有 PDFKit 操作序列化，远离主线程 PDFView 渲染竞态
    private let pdfQueue = DispatchQueue(label: "com.pdfextractor.pdfqueue", qos: .userInitiated)
    
    // 常用 OCR 易错错字本地校对字典
    private let ocrCorrectionMap: [String: String] = [
        "面且": "而且",
        "我门": "我们",
        "系境": "系统",
        "支特": "支持",
        "确保": "确保",
        "功育": "功能",
        "用广": "用户",
        "设量": "设置",
        "提取码": "提取",
        "温道": "通道",
        "相回": "相同"
    ]
    
    init() {}
    
    /// 加载 PDF 文件并对其进行初始化扫描
    func loadPDF(url: URL) -> Bool {
        // 主线程加载 PDFDocument 仅用作 UI 预览和总页数获取
        guard let doc = PDFDocument(url: url) else { return false }
        self.pdfDocument = doc
        self.pdfURL = url
        self.pdfFileName = url.lastPathComponent
        self.pdfTotalPages = doc.pageCount
        
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
        self.currentLoadToken = token
        
        self.logOutput = "文件成功加载: \(url.lastPathComponent)\n"
        self.currentStatus = "就绪，正在自动分析水印词..."
        
        // 启动后台队列独立加载 PDFDocument 分析水印词
        analyzeWatermarksInQueue(url: url, token: token)
        return true
    }
    
    /// 清除当前加载的文件并强行中断正在运行的后台任务
    func clear() {
        self.currentLoadToken = nil
        self.isAnalyzingWatermarks = false
        self.pdfDocument = nil
        self.pdfURL = nil
        self.pdfFileName = ""
        self.pdfFileSize = ""
        self.pdfTotalPages = 0
        self.watermarkCandidates = []
        self.progress = 0.0
        self.isProcessing = false
        self.currentStatus = "未加载文件"
        self.logOutput = ""
        
        cancelPDFExtraction()
    }
    
    /// 在后台串行队列中独立创建 PDFDocument 实例分析水印词，物理隔离主线程的 PDFDocument
    private func analyzeWatermarksInQueue(url: URL, token: UUID) {
        self.isAnalyzingWatermarks = true
        pdfQueue.async { [weak self] in
            guard let self = self else { return }
            // 从 URL 独立加载实例，规避多线程读取同一实例崩溃
            guard let doc = PDFDocument(url: url) else {
                DispatchQueue.main.async { [weak self] in
                    self?.isAnalyzingWatermarks = false
                }
                return
            }
            
            var counts: [String: Int] = [:]
            let pageCount = doc.pageCount
            let maxPagesToScan = min(pageCount, 30)
            
            for i in 0..<maxPagesToScan {
                guard self.currentLoadToken == token else { return }
                guard let page = doc.page(at: i) else { continue }
                let selections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
                for sel in selections {
                    if let text = sel.string?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !text.isEmpty {
                        if text.count >= 2 && text.count <= 30 {
                            counts[text, default: 0] += 1
                        }
                    }
                }
            }
            
            let threshold = max(2, Int(Double(maxPagesToScan) * 0.2))
            let candidates = counts.filter { $0.value >= threshold }
                .map { WatermarkCandidate(text: $0.key, occurrenceCount: $0.value, isSelected: true) }
                .sorted { $0.occurrenceCount > $1.occurrenceCount }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.currentLoadToken == token else { return }
                
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
        }
    }
    
    /// 解析页码范围输入字符串，返回需要处理的 1-indexed 页码列表
    func parsePageRange(_ rangeStr: String, maxPages: Int) -> [Int] {
        let trimmed = rangeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Array(1...maxPages)
        }
        
        var pages = Set<Int>()
        // 兼容中文逗号和英文逗号
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ",，"))
        for part in parts {
            let cleanPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanPart.contains("-") {
                let rangeParts = cleanPart.components(separatedBy: "-")
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
    
    /// 执行文字提取与去水印任务
    func extractText(
        activeWatermarks: Set<String>,
        customWatermarks: String,
        ignoreCase: Bool,
        mode: ExtractionMode,
        eraseImageWatermark: Bool,
        pageRangeString: String,
        completion: @escaping (String, URL?, Double) -> Void // 增加单页平均耗时返回
    ) {
        guard let url = pdfURL else { return }
        guard !isProcessing else { return }
        
        let token = UUID()
        self.currentExtractTokenSafe = token
        
        isProcessing = true
        isCancelledSafe = false
        progress = 0.0
        etaString = "" // 重置 ETA
        currentStatus = "准备开始处理..."
        logOutput += "\n=== 开始执行文字提取与去水印 ===\n"
        
        // 解析自定义水印词
        let customList = customWatermarks
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let allWatermarkFilters = activeWatermarks.union(customList)
        logOutput += "生效的水印过滤词: \(allWatermarkFilters.sorted().joined(separator: ", "))\n"
        logOutput += "模式: \(mode.rawValue)\n"
        logOutput += "图像擦除水印: \(eraseImageWatermark ? "开启" : "关闭")\n"
        
        let targetPages = parsePageRange(pageRangeString, maxPages: pdfTotalPages)
        logOutput += "计划提取页码: \(targetPages.map { String($0) }.joined(separator: ", ")) (共 \(targetPages.count) 页)\n"
        
        // 目标存盘路径 (与 PDF 所在文件夹同名同路径下的 .txt 文件)
        let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
        
        // 初始化空文件
        do {
            try "".write(to: txtURL, atomically: true, encoding: .utf8)
        } catch {
            logOutput += "⚠️ 警告：初始化本地写盘文件失败 \(error.localizedDescription)\n"
        }
        
        let startTime = Date()
        
        // 将主要 PDF 运算分发到后台串行队列
        pdfQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.currentExtractTokenSafe == token else { return }
            
            // 1. 后台线程独立重新加载 PDFDocument，解决主线程/子线程共享 PDFKit 实例崩溃问题
            guard let doc = PDFDocument(url: url) else {
                self.updateStatus("❌ 无法以安全模式在后台读取 PDF 文档。")
                DispatchQueue.main.async { [weak self] in
                    self?.isProcessing = false
                }
                return
            }
            
            var memoryBuffer = ""
            let totalToProcess = targetPages.count
            
            for (index, pageIndex) in targetPages.enumerated() {
                // 安全校验，防任务重入污染
                guard self.currentExtractTokenSafe == token else {
                    print("[提取提示] 检测到新任务或已清除，旧后台线程已安全退出。")
                    return
                }
                
                // 实时中止检查
                if self.isCancelledSafe {
                    self.updateStatus("❌ 处理被用户中止。已提取的数据已安全存在本地。")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.isProcessing = false
                        completion(memoryBuffer, txtURL, 0.0)
                    }
                    return
                }
                
                self.updateStatus("正在处理第 \(pageIndex) 页 (总进度: \(index + 1) / \(totalToProcess))...")
                
                var pageText = ""
                
                // OCR 内存释放隔离，解决大文件 OCR 时 OOM 的问题
                autoreleasepool {
                    // PDFKit 页码索引为 0-based，故实际页码为 pageIndex - 1
                    guard let page = doc.page(at: pageIndex - 1) else {
                        return
                    }
                    
                    pageText = self.processPage(
                        page: page,
                        pageIndex: pageIndex,
                        watermarkFilters: allWatermarkFilters,
                        ignoreCase: ignoreCase,
                        mode: mode,
                        eraseImageWatermark: eraseImageWatermark
                    )
                }
                
                // 本地预设纠错替换
                pageText = self.applyLocalCorrection(pageText)
                
                let pageHeader = "\n[第 \(pageIndex) 页]\n"
                let pageContent = pageText + "\n"
                
                memoryBuffer += pageHeader + pageContent
                
                guard self.currentExtractTokenSafe == token else { return }
                
                // 追加写盘
                do {
                    if !FileManager.default.fileExists(atPath: txtURL.path) {
                        try "".write(to: txtURL, atomically: true, encoding: .utf8)
                    }
                    let fileHandle = try FileHandle(forWritingTo: txtURL)
                    try fileHandle.seekToEnd()
                    if let writeData = (pageHeader + pageContent).data(using: .utf8) {
                        try fileHandle.write(contentsOf: writeData)
                    }
                    try fileHandle.close()
                } catch {
                    self.updateStatus("⚠️ 实时追加写盘失败: \(error.localizedDescription)")
                }
                
                self.updateProgress(Double(index + 1) / Double(totalToProcess))
                
                // 实时计算剩余时间 (ETA)
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
                
                DispatchQueue.main.async { [weak self] in
                    self?.etaString = etaText
                }
            }
            
            guard self.currentExtractTokenSafe == token else { return }
            
            let totalTime = Date().timeIntervalSince(startTime)
            let avgPageTime = totalToProcess > 0 ? totalTime / Double(totalToProcess) : 0.0
            
            self.updateStatus("🎉 处理完成！结果已自动保存。平均每页耗时: \(String(format: "%.2f", avgPageTime)) 秒。")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isProcessing = false
                completion(memoryBuffer, txtURL, avgPageTime)
            }
        }
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentStatus = status
            self.logOutput += status + "\n"
        }
    }
    
    private func updateProgress(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.progress = val
        }
    }
    
    /// 常用 OCR 纠错本地替换
    private func applyLocalCorrection(_ text: String) -> String {
        var corrected = text
        for (wrong, right) in ocrCorrectionMap {
            corrected = corrected.replacingOccurrences(of: wrong, with: right)
        }
        return corrected
    }
    
    private func processPage(
        page: PDFPage,
        pageIndex: Int,
        watermarkFilters: Set<String>,
        ignoreCase: Bool,
        mode: ExtractionMode,
        eraseImageWatermark: Bool
    ) -> String {
        let allSelections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
        var watermarkSelections: [PDFSelection] = []
        var normalTextPieces: [String] = []
        var normalCharCount = 0
        
        for sel in allSelections {
            guard let text = sel.string else { continue }
            
            if isWatermark(text: text, filters: watermarkFilters, ignoreCase: ignoreCase) {
                watermarkSelections.append(sel)
            } else {
                normalTextPieces.append(text)
                normalCharCount += text.count
            }
        }
        
        let shouldOCR: Bool
        switch mode {
        case .smart:
            shouldOCR = normalCharCount < 40
        case .textOnly:
            shouldOCR = false
        case .ocrOnly:
            shouldOCR = true
        }
        
        var pageResult = ""
        
        if shouldOCR {
            self.updateStatus("第 \(pageIndex) 页: 检测为扫描件图片，正在启动本地 Vision OCR 识别...")
            
            if let image = renderPageToImage(page: page, watermarkSelections: eraseImageWatermark ? watermarkSelections : []) {
                let semaphore = DispatchSemaphore(value: 0)
                var rawOCRText = ""
                
                performLocalOCR(on: image) { recognized in
                    rawOCRText = recognized
                    semaphore.signal()
                }
                
                // OCR 阻塞等待加上 60 秒限时，防止因系统异常导致后台线程永久死锁卡死
                let waitResult = semaphore.wait(timeout: .now() + 60.0)
                if waitResult == .timedOut {
                    self.updateStatus("⚠️ 第 \(pageIndex) 页: Vision OCR 执行超时（超过60秒），已跳过。")
                } else {
                    let cleanedOCRText = self.cleanText(rawOCRText, filters: watermarkFilters, ignoreCase: ignoreCase)
                    pageResult = cleanedOCRText
                    self.updateStatus("第 \(pageIndex) 页: OCR 识别并净化完成。")
                }
            } else {
                self.updateStatus("第 \(pageIndex) 页: 渲染页面图片失败，退回至提取文本。")
                pageResult = normalTextPieces.joined(separator: "\n")
            }
        } else {
            self.updateStatus("第 \(pageIndex) 页: 检测为包含可选中的活字正文，已直接提取并剔除活字水印。")
            
            var cleanedTextPieces: [String] = []
            var lastWasEmpty = false
            for piece in normalTextPieces {
                let trimmed = piece.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if !lastWasEmpty {
                        cleanedTextPieces.append("")
                        lastWasEmpty = true
                    }
                } else {
                    cleanedTextPieces.append(piece)
                    lastWasEmpty = false
                }
            }
            pageResult = cleanedTextPieces.joined(separator: "\n")
        }
        
        return pageResult
    }
    
    private func isWatermark(text: String, filters: Set<String>, ignoreCase: Bool) -> Bool {
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
    
    private func cleanText(_ text: String, filters: Set<String>, ignoreCase: Bool) -> String {
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
    
    private func replaceIgnoreCase(in text: String, target: String, with replacement: String) -> String {
        var result = text
        while let range = result.range(of: target, options: .caseInsensitive) {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
    
    private func renderPageToImage(page: PDFPage, watermarkSelections: [PDFSelection]) -> NSImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3.0
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
        
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
    
    private func performLocalOCR(on image: NSImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion("")
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        let request = VNRecognizeTextRequest { (request, error) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion("")
                return
            }
            
            var recognizedText = ""
            for observation in observations {
                if let candidate = observation.topCandidates(1).first {
                    recognizedText += candidate.string + "\n"
                }
            }
            completion(recognizedText)
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        
        do {
            try requestHandler.perform([request])
        } catch {
            print("Vision OCR 引擎执行失败: \(error)")
            completion("")
        }
    }
}

// MARK: - 支持的文字提取模式
enum ExtractionMode: String, CaseIterable, Identifiable, Codable {
    case smart = "智能提取（推荐）"
    case textOnly = "仅提取活字（极速）"
    case ocrOnly = "强制全部 OCR（适合扫描件）"
    
    var id: String { self.rawValue }
}
