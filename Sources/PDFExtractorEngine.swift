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
    
    // 物理页码对应的提取文本缓存，支持四栏工作区翻页同步联动
    @Published var extractedPagesText: [Int: String] = [:]
    

    
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
    
    // 串行 PDF 提取专用队列，彻底将所有 PDFKit 操作序列化，远离主线程 PDFView 渲染竞态
    private let pdfQueue = DispatchQueue(label: "com.pdfextractor.pdfqueue", qos: .userInitiated)
    
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
    
    // 用于通知 UI 加载失败时的错误信息 (P2-6 修复)
    @Published var errorMessage: String? = nil
    
    /// 在后台异步加载 PDF 文件并进行水印词初始化扫描，规避大文件同步加载阻塞主线程 (P2-3, P2-6 修复)
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
        
        // 移至后台队列加载，完全避开主线程卡顿
        pdfQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 确保没有被更新的加载任务覆盖
            guard self.currentLoadTokenSafe == token else { return }
            
            guard let doc = PDFDocument(url: url) else {
                DispatchQueue.main.async {
                    guard self.currentLoadTokenSafe == token else { return }
                    self.pdfDocument = nil
                    self.pdfFileName = ""
                    self.pdfFileSize = ""
                    self.pdfTotalPages = 0
                    self.isAnalyzingWatermarks = false
                    self.currentStatus = "加载 PDF 失败"
                    self.logOutput += "错误: 无法解析或加载该 PDF 文件。\n"
                    self.errorMessage = "无法解析或加载此 PDF 文件。该文件可能已损坏、被加密或格式不正确。"
                }
                return
            }
            
            DispatchQueue.main.async {
                guard self.currentLoadTokenSafe == token else { return }
                self.pdfDocument = doc
                self.pdfTotalPages = doc.pageCount
                self.logOutput += "文件成功加载: \(url.lastPathComponent)\n"
                self.currentStatus = "就绪，正在自动分析水印词..."
                
                // 加载成功后，在后台启动水印词分析任务
                self.analyzeWatermarksInQueue(url: url, token: token)
            }
        }
    }
    
    /// 清除当前加载的文件并强行中断正在运行的后台任务
    func clear() {
        // 先中止所有后台任务并递增 Token，确保旧任务立即失效不再写入
        cancelPDFExtraction()
        self.currentLoadTokenSafe = nil
        self.currentExtractTokenSafe = nil
        
        // 然后安全重置全部 UI 状态
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
                guard self.currentLoadTokenSafe == token else { return }
                guard let page = doc.page(at: i) else { continue }
                let selections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
                for sel in selections {
                    if let text = sel.string?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !text.isEmpty {
                        if text.count >= 2 && text.count <= 30 {
                            // 限制 counts 字典容量为最大 5000 条，保护内存占用恒定 O(1)
                            if counts.count < 5000 || counts[text] != nil {
                                counts[text, default: 0] += 1
                            }
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
        }
    }
    
    /// 解析页码范围输入字符串，返回需要处理的 1-indexed 页码列表 (支持中英文多种连接符)
    func parsePageRange(_ rangeStr: String, maxPages: Int) -> [Int] {
        let trimmed = rangeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Array(1...maxPages)
        }
        
        var pages = Set<Int>()
        // 兼容中文逗号和英文逗号
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
    
    /// 执行文字提取与去水印任务 (完整三大去水印模式支持)
    func extractText(
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
        
        DispatchQueue.main.async { [weak self] in
            self?.extractedPagesText = [:]
        }
        
        // 解析自定义水印词
        let customList = customWatermarks
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let allWatermarkFilters = activeWatermarks.union(customList)
        if enableWatermarkFilter {
            logOutput += "生效的水印过滤词: \(allWatermarkFilters.sorted().joined(separator: ", "))\n"
        } else {
            logOutput += "🚫 水印识别与过滤开关已关闭，保留原汁原味提取。\n"
        }
        logOutput += "正文提取通道: \(mode.rawValue)\n"
        logOutput += "去水印工作模式: \(watermarkRemovalMode.rawValue)\n"
        logOutput += "图像擦除水印: \(eraseImageWatermark ? "开启" : "关闭")\n"
        
        let targetPages = parsePageRange(pageRangeString, maxPages: pdfTotalPages)
        logOutput += "计划提取页码: \(targetPages.map { String($0) }.joined(separator: ", ")) (共 \(targetPages.count) 页)\n"
        
        // 目标存盘路径 (同时生成 TXT 与 MD 文件)
        let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
        let mdURL = url.deletingPathExtension().appendingPathExtension("md")
        
        let startTime = Date()
        
        // 将主要 PDF 运算分发到后台串行队列，包含初次空文件写入以防主线程卡死
        pdfQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.currentExtractTokenSafe == token else { return }
            
            // 异步初始化空文件，保护主线程不发生 IO 卡死
            do {
                try "".write(to: txtURL, atomically: true, encoding: .utf8)
                let mdTitle = "# \(self.pdfFileName) 提取正文 (去水印)\n\n"
                try mdTitle.write(to: mdURL, atomically: true, encoding: .utf8)
            } catch {
                self.updateStatus("⚠️ 警告：初始化本地写盘文件失败 \(error.localizedDescription)")
            }
            
            // 后台线程独立重新加载 PDFDocument，解决主线程/子线程共享 PDFKit 实例崩溃问题
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
                        completion(memoryBuffer, txtURL, mdURL, 0.0)
                    }
                    return
                }
                
                self.updateStatus("正在处理第 \(pageIndex) 页 (总进度: \(index + 1) / \(totalToProcess))...")
                
                var pageText = ""
                
                // OCR 内存释放隔离，解决大文件 OCR 时 OOM 的问题
                autoreleasepool {
                    guard let page = doc.page(at: pageIndex - 1) else { return }
                    
                    pageText = self.processPage(
                        page: page,
                        pageIndex: pageIndex,
                        watermarkFilters: allWatermarkFilters,
                        ignoreCase: ignoreCase,
                        mode: mode,
                        watermarkRemovalMode: watermarkRemovalMode,
                        enableWatermarkFilter: enableWatermarkFilter,
                        eraseImageWatermark: eraseImageWatermark
                    )
                }
                
                // 本地预设纠错替换
                pageText = self.applyLocalCorrection(pageText)
                
                let pageTextToSave = pageText
                DispatchQueue.main.async { [weak self] in
                    self?.extractedPagesText[pageIndex] = pageTextToSave
                }
                
                let pageHeader = "\n[第 \(pageIndex) 页]\n"
                let mdPageHeader = "\n## 第 \(pageIndex) 页\n\n"
                let pageContent = pageText + "\n"
                
                memoryBuffer += pageHeader + pageContent
                
                guard self.currentExtractTokenSafe == token else { return }
                
                // 追加写盘 (TXT)
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
                    self.updateStatus("⚠️ 实时追加 TXT 写盘失败: \(error.localizedDescription)")
                }
                
                // 追加写盘 (Markdown)
                do {
                    if !FileManager.default.fileExists(atPath: mdURL.path) {
                        let mdTitle = "# \(self.pdfFileName) 提取正文 (去水印)\n\n"
                        try mdTitle.write(to: mdURL, atomically: true, encoding: .utf8)
                    }
                    let fileHandle = try FileHandle(forWritingTo: mdURL)
                    try fileHandle.seekToEnd()
                    if let writeData = (mdPageHeader + pageContent).data(using: .utf8) {
                        try fileHandle.write(contentsOf: writeData)
                    }
                    try fileHandle.close()
                } catch {
                    self.updateStatus("⚠️ 实时追加 Markdown 写盘失败: \(error.localizedDescription)")
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
                self.etaString = ""
                completion(memoryBuffer, txtURL, mdURL, avgPageTime)
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
            // 限制日志最大长度，防止数百页 PDF 处理时内存与 SwiftUI 渲染卡顿
            if self.logOutput.count > 50000 {
                let lines = self.logOutput.components(separatedBy: "\n")
                if lines.count > 200 {
                    self.logOutput = "...(旧日志已截断)...\n" + lines.suffix(200).joined(separator: "\n")
                }
            }
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
    
    /// 底层分流与去水印核心算法 (三种不同 PDF 水印/正文场景)
    private func processPage(
        page: PDFPage,
        pageIndex: Int,
        watermarkFilters: Set<String>,
        ignoreCase: Bool,
        mode: ExtractionMode,
        watermarkRemovalMode: WatermarkRemovalMode,
        enableWatermarkFilter: Bool,
        eraseImageWatermark: Bool
    ) -> String {
        let allSelections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
        
        // 1. 全局开关控制：若禁用去水印，则过滤词为空
        let activeFilters = enableWatermarkFilter ? watermarkFilters : Set<String>()
        
        // 2. 诊断与分流策略
        var resolvedMode = watermarkRemovalMode
        if resolvedMode == .auto {
            let rawCharCount = allSelections.reduce(0) { $0 + ($1.string?.count ?? 0) }
            if rawCharCount > 100 {
                resolvedMode = .modeA // 正文字词量大 ➡️ 模式 A (纯文本过滤)
            } else {
                resolvedMode = (rawCharCount > 0) ? .modeB : .modeC // 文字少且有可选字 ➡️ 模式 B，完全无字 ➡️ 模式 C
            }
        }
        
        // 3. 通道抉择 (结合用户强制指定的 OCR 设置)
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
            // 需要跑 OCR 的逻辑 (模式 B 或 模式 C)
            self.updateStatus("第 \(pageIndex) 页: 正在启用本地 Vision OCR 识别...")
            
            var maskSelections: [PDFSelection] = []
            if resolvedMode == .modeB && enableWatermarkFilter {
                // 模式 B：获取用于像素抹白的水印 Bounds 集合
                for sel in allSelections {
                    guard let text = sel.string else { continue }
                    if isWatermark(text: text, filters: activeFilters, ignoreCase: ignoreCase) {
                        maskSelections.append(sel)
                    }
                }
            }
            
            // 物理抹白，如果无需抹白或模式 C，maskSelections 传入空即可
            let coverSelections = eraseImageWatermark ? maskSelections : (resolvedMode == .modeB ? maskSelections : [])
            
            if let cgImage = renderPageToCGImage(page: page, watermarkSelections: coverSelections) {
                let semaphore = DispatchSemaphore(value: 0)
                var rawOCRText = ""
                
                performLocalOCR(on: cgImage) { recognized in
                    rawOCRText = recognized
                    semaphore.signal()
                }
                
                let waitResult = semaphore.wait(timeout: .now() + 60.0)
                if waitResult == .timedOut {
                    self.updateStatus("⚠️ 第 \(pageIndex) 页: Vision OCR 执行超时（超过60秒），已跳过。")
                } else {
                    if resolvedMode == .modeC && enableWatermarkFilter {
                        // 模式 C：OCR 识别出全部内容后，进行字符串净化后处理
                        pageResult = self.cleanText(rawOCRText, filters: activeFilters, ignoreCase: ignoreCase)
                    } else {
                        pageResult = rawOCRText
                    }
                    self.updateStatus("第 \(pageIndex) 页: OCR 识别与去水印处理完成。")
                }
            } else {
                self.updateStatus("第 \(pageIndex) 页: 渲染页面物理图像失败。")
            }
        } else {
            // 文字提取逻辑 (模式 A)
            self.updateStatus("第 \(pageIndex) 页: 正在以纯文本模式提取正文...")
            var normalTextPieces: [String] = []
            var lastWasEmpty = false
            
            for sel in allSelections {
                guard let text = sel.string else { continue }
                
                // 模式 A 独享的严格完全匹配过滤，彻底防止 contains 包含匹配误杀正文
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
            self.updateStatus("第 \(pageIndex) 页: 文本过滤与提取完成。")
        }
        
        return pageResult
    }
    
    /// 水印模糊包含比对 (适用于扫描件 OCR 物理擦除定位)
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
    
    /// 水印严格整行匹配判定 (模式 A 核心防误杀机制)
    private func isWatermarkStrict(text: String, filters: Set<String>, ignoreCase: Bool) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.isEmpty { return false }
        
        let textToCompare = ignoreCase ? cleanText.lowercased() : cleanText
        for filter in filters {
            let filterToCompare = ignoreCase ? filter.lowercased() : filter
            // 必须整行与水印匹配词完全相等，或者是长水印的前后截断相等，才作为水印抛弃，绝对不伤及正文
            if textToCompare == filterToCompare {
                return true
            }
        }
        return false
    }
    
    /// 水印清理
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
    
    /// 高阶物理渲染：直接生成底层的 CGImage，极大地节省了 NSImage 包装的转码时延和内存泄露
    private func renderPageToCGImage(page: PDFPage, watermarkSelections: [PDFSelection]) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        // 动态计算缩放比例：确保渲染分辨率最大边不超过 4096 像素，防止超大页面 OOM 崩溃
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
        
        // 模式 B：执行物理抹白遮盖
        NSColor.white.set()
        for selection in watermarkSelections {
            let bounds = selection.bounds(for: page)
            // 微微向外扩张 1.5 pt，保证完全将可能包含抗锯齿边缘的笔画完全覆盖遮白
            let coverRect = bounds.insetBy(dx: -1.5, dy: -1.5)
            coverRect.fill()
        }
        
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
    
    /// 本地 Vision OCR 识别算法 (并发指派，规避主提取队列死锁)
    private func performLocalOCR(on cgImage: CGImage, completion: @escaping (String) -> Void) {
        // 将同步阻塞的 Vision perform 操作指派到系统后台全局并发队列，不占用 pdfQueue 串行提取队列的资源
        DispatchQueue.global(qos: .userInitiated).async {
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
}

// MARK: - 支持的文字提取模式
enum ExtractionMode: String, CaseIterable, Identifiable, Codable {
    case smart = "智能提取（推荐）"
    case textOnly = "仅提取活字（极速）"
    case ocrOnly = "强制全部 OCR（适合扫描件）"
    
    var id: String { self.rawValue }
}
