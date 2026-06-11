import SwiftUI
import PDFKit
import Vision
import UniformTypeIdentifiers

// MARK: - App 入口
@main
struct PDFExtractorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar) // 隐藏标题栏，使 UI 更一体化、现代化
    }
}

// MARK: - 核心 PDF 处理与 OCR / 本地 AI 引擎 (体验与 Bug 加固版)
class PDFExtractorEngine: NSObject, ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var currentStatus: String = "未加载文件"
    @Published var logOutput: String = ""
    @Published var pdfFileName: String = ""
    @Published var pdfFileSize: String = ""
    @Published var pdfTotalPages: Int = 0
    
    // 是否正在后台异步扫描水印词，用以防范与文本提取任务的 PDFKit 竞态冲突
    @Published var isAnalyzingWatermarks = false
    
    // 自动扫描识别出来的疑似水印词列表
    @Published var watermarkCandidates: [WatermarkCandidate] = []
    
    struct WatermarkCandidate: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let occurrenceCount: Int
        var isSelected: Bool = true
    }
    
    private var pdfDocument: PDFDocument?
    private var pdfURL: URL?
    
    // 中止 PDF 提取信号
    @Published var isCancelled = false
    
    // === 本地 AI 净化模块状态 ===
    @Published var aiApiBaseUrl: String = "http://localhost:11434/v1" // 默认 Ollama API 地址
    @Published var aiApiKey: String = ""
    @Published var aiSelectedModel: String = ""
    @Published var aiModels: [String] = []
    @Published var isAIFetchingModels = false
    @Published var isAIProcessing = false
    @Published var aiProgressStatus: String = ""
    @Published var aiResultText: String = ""
    
    // AI 自动保存的 TXT 文件路径
    @Published var aiTxtFileURL: URL?
    
    // 用以控制和主动中止当前流式 AI 推理任务的 Session 与 Task 句柄
    private var currentAISession: URLSession?
    private var currentAITask: URLSessionDataTask?
    
    // 流式 SSE 文本分块数据缓冲区，100% 规避 TCP 包截断与多字节字符乱码问题
    private var streamBuffer = Data()
    
    // 模型列表响应结构
    struct AIModelResponse: Codable {
        let data: [AIModelData]
    }
    struct AIModelData: Codable {
        let id: String
    }
    
    // 用于追踪每一次 PDF 加载的唯一标识，防范清除或重新加载时的时序竞态
    private var currentLoadToken: UUID?

    override init() {
        super.init()
    }
    
    /// 加载 PDF 文件并对其进行初始化扫描
    func loadPDF(url: URL) -> Bool {
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
        
        // 自动分析疑似水印
        analyzeWatermarks(doc, token: token)
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
        
        // AI 状态清除
        self.aiResultText = ""
        self.aiProgressStatus = ""
        self.aiTxtFileURL = nil
        
        // 取消正在进行的任务
        cancelPDFExtraction()
        cancelAIProcessing()
    }
    
    /// 【异步主线程安全优化】：扫描 PDF 的前若干页，统计高频出现的疑似水印文字。
    /// 计算过程完全放入后台 global 线程，彻底规避大文件拖入时引起 UI 主线程假死和彩虹球问题。
    private func analyzeWatermarks(_ doc: PDFDocument, token: UUID) {
        self.isAnalyzingWatermarks = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var counts: [String: Int] = [:]
            let pageCount = doc.pageCount
            let maxPagesToScan = min(pageCount, 30) // 最多扫描前30页用于水印分析
            
            for i in 0..<maxPagesToScan {
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
            
            // 筛选出在超过 20% 的已扫描页面中重复出现的文本块
            let threshold = max(2, Int(Double(maxPagesToScan) * 0.2))
            let candidates = counts.filter { $0.value >= threshold }
                .map { WatermarkCandidate(text: $0.key, occurrenceCount: $0.value, isSelected: true) }
                .sorted { $0.occurrenceCount > $1.occurrenceCount }
            
            // 计算完毕后回到主线程更新 UI 绑定
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // 如果在后台计算期间，文件已被清除或替换，则丢弃本次计算结果
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
    
    /// 执行文字提取与去水印任务 (包含实时写盘加固和中止拦截)
    func extractText(
        activeWatermarks: Set<String>,
        customWatermarks: String,
        ignoreCase: Bool,
        mode: ExtractionMode,
        eraseImageWatermark: Bool,
        completion: @escaping (String, URL?) -> Void
    ) {
        guard let doc = pdfDocument, let url = pdfURL else { return }
        guard !isProcessing else { return } // 防重入保护
        
        isProcessing = true
        isCancelled = false
        progress = 0.0
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
        
        // 目标存盘路径 (与 PDF 所在文件夹同名同路径下的 .txt 文件)
        let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
        
        // 【崩溃保护】：在提取开始前，清空旧的 TXT 文件，防止重复提取时内容叠加
        do {
            try "".write(to: txtURL, atomically: true, encoding: .utf8)
        } catch {
            logOutput += "⚠️ 警告：初始化本地写盘文件失败 \(error.localizedDescription)\n"
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let totalPages = doc.pageCount
            var memoryBuffer = ""
            
            for i in 0..<totalPages {
                let pageIndex = i + 1
                
                // 【提取中止拦截点】：在处理每一页前先核实用户是否点击了“取消”
                if self.isCancelled {
                    self.updateStatus("❌ 处理被用户中止。已提取的数据已安全存在本地。")
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        completion(memoryBuffer, txtURL)
                    }
                    return
                }
                
                self.updateStatus("正在处理第 \(pageIndex) / \(totalPages) 页...")
                
                guard let page = doc.page(at: i) else {
                    self.updateProgress(Double(pageIndex) / Double(totalPages))
                    continue
                }
                
                let pageText = self.processPage(
                    page: page,
                    pageIndex: pageIndex,
                    watermarkFilters: allWatermarkFilters,
                    ignoreCase: ignoreCase,
                    mode: mode,
                    eraseImageWatermark: eraseImageWatermark
                )
                
                let pageHeader = "\n[第 \(pageIndex) 页]\n"
                let pageContent = pageText + "\n"
                
                // 1. 将数据缓存在内存变量中，用于界面上的截断预览
                memoryBuffer += pageHeader + pageContent
                
                // 2. 【实时追加写盘与删除重建防护】：即使在提取过程中用户在 Finder 意外删除了 TXT 文本，程序也会自动重建它并继续追加，绝对不会丢失后续页面数据
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
                
                self.updateProgress(Double(pageIndex) / Double(totalPages))
            }
            
            self.updateStatus("🎉 处理完成！结果已自动保存。")
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(memoryBuffer, txtURL)
            }
        }
    }
    
    /// 主动中止当前的文字提取线程
    func cancelPDFExtraction() {
        if isProcessing {
            isCancelled = true
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
    
    /// 处理单个页面，根据模式决定是直接提取活字还是执行 OCR (包含空行合并净化排版)
    private func processPage(
        page: PDFPage,
        pageIndex: Int,
        watermarkFilters: Set<String>,
        ignoreCase: Bool,
        mode: ExtractionMode,
        eraseImageWatermark: Bool
    ) -> String {
        // 1. 获取页面上所有的可选中行
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
        
        // 2. 根据提取模式判断是否需要启动 OCR
        let shouldOCR: Bool
        switch mode {
        case .smart:
            // 智能模式：如果过滤掉水印后，剩下的非水印活字文字数太少（< 40 个字符），则认为该页大概率是纯图片/扫描页
            shouldOCR = normalCharCount < 40
        case .textOnly:
            shouldOCR = false
        case .ocrOnly:
            shouldOCR = true
        }
        
        var pageResult = ""
        
        if shouldOCR {
            self.updateStatus("第 \(pageIndex) 页: 检测为扫描件图片，正在启动本地 Vision OCR 识别...")
            
            // 渲染高分辨率 PDF 页面。如果开启了图像去水印，将在渲染时用白色覆盖水印 bounding box 区域
            if let image = renderPageToImage(page: page, watermarkSelections: eraseImageWatermark ? watermarkSelections : []) {
                let semaphore = DispatchSemaphore(value: 0)
                var rawOCRText = ""
                
                performLocalOCR(on: image) { recognized in
                    rawOCRText = recognized
                    semaphore.signal()
                }
                
                _ = semaphore.wait(timeout: .distantFuture)
                
                // OCR 文本无损后处理净化：在文本中移除识别出来的残留水印字眼，确保正文不被遮挡
                let cleanedOCRText = self.cleanText(rawOCRText, filters: watermarkFilters, ignoreCase: ignoreCase)
                pageResult = cleanedOCRText
                self.updateStatus("第 \(pageIndex) 页: OCR 识别并净化完成。")
            } else {
                self.updateStatus("第 \(pageIndex) 页: 渲染页面图片失败，退回至提取文本。")
                pageResult = normalTextPieces.joined(separator: "\n")
            }
        } else {
            self.updateStatus("第 \(pageIndex) 页: 检测为包含可选中的活字正文，已直接提取并剔除活字水印。")
            
            // 【排版净化】：过滤连续的无意义空行，保留段落排版的可读性，消除堆积换行
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
    
    /// 判断是否匹配水印过滤词
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
    
    /// 文本后处理与排版优化：在识别好的文字中精准剔除水印字词，合并连续空行
    private func cleanText(_ text: String, filters: Set<String>, ignoreCase: Bool) -> String {
        var cleaned = text
        for filter in filters {
            if filter.count >= 2 { // 过滤过短的无意义字符
                if ignoreCase {
                    cleaned = replaceIgnoreCase(in: cleaned, target: filter, with: "")
                } else {
                    cleaned = cleaned.replacingOccurrences(of: filter, with: "")
                }
            }
        }
        
        // 【排版优化】：清理并压缩由于剔除水印产生的多余连续换行，只保留合理间隔
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
    
    /// 将 PDF 页面渲染为用于 OCR 的高分辨率图像，并对水印 selections 的矩形进行细粒度涂白覆盖
    private func renderPageToImage(page: PDFPage, watermarkSelections: [PDFSelection]) -> NSImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        
        // 缩放比例 3.0 相当于 216 DPI，可以在保证 OCR 极高精度的情况下优化计算速度与内存占用
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
        
        // 1. 填充白色背景
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor.white.set()
        rect.fill()
        
        // 2. 缩放坐标系，以便直接用 PDFPage 自己的 bounds 绘图
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        
        // 3. 绘制 PDF 页面
        page.draw(with: .mediaBox, to: context.cgContext)
        
        // 4. 水印擦除：用白色填充水印 selections 的 bounds
        NSColor.white.set()
        for selection in watermarkSelections {
            let bounds = selection.bounds(for: page)
            // 向外微调 1.5 个像素，防止笔画残留阴影干扰 OCR
            let coverRect = bounds.insetBy(dx: -1.5, dy: -1.5)
            coverRect.fill()
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
    
    /// 调用 macOS 原生 Vision 引擎进行多语言高精度 OCR (100% 离线，安全保障)
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
        
        // 设置多语言识别，包括中文（简体和繁体）和英文
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        
        do {
            try requestHandler.perform([request])
        } catch {
            print("Vision OCR 引擎执行失败: \(error)")
            completion("")
        }
    }
    
    // === 本地 AI 净化方法 ===
    
    /// 连接本地 AI 并获取模型列表
    func fetchAIModels() {
        guard let url = URL(string: aiApiBaseUrl + "/models") else {
            self.updateAIProgressStatus("❌ 无效的 API 服务地址")
            return
        }
        
        isAIFetchingModels = true
        updateAIProgressStatus("正在获取模型列表...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0 // 延长至 15 秒以允许本地 AI 服务启动或唤醒
        
        if !aiApiKey.isEmpty {
            request.addValue("Bearer \(aiApiKey)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.isAIFetchingModels = false
            }
            
            if let error = error {
                self.updateAIProgressStatus("❌ 连接失败: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                self.updateAIProgressStatus("❌ 服务器未返回数据")
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(AIModelResponse.self, from: data)
                let modelIds = decoded.data.map { $0.id }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.aiModels = modelIds
                    if let first = modelIds.first {
                        self.aiSelectedModel = first
                    }
                    self.updateAIProgressStatus("✅ 成功拉取到 \(modelIds.count) 个本地模型")
                }
            } catch {
                // 尝试解析非标结构
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let dataArray = json["data"] as? [[String: Any]] {
                    let ids = dataArray.compactMap { $0["id"] as? String }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.aiModels = ids
                        if let first = ids.first {
                            self.aiSelectedModel = first
                        }
                        self.updateAIProgressStatus("✅ 成功获取 \(ids.count) 个模型")
                    }
                } else {
                    self.updateAIProgressStatus("❌ 无法解析模型列表，请确认是否兼容 OpenAI")
                }
            }
        }.resume()
    }
    
    /// 发送文本至本地 AI 进行格式排版与字词净化（24小时超长超时，开启流式，并支持客户端主动中断以释放 GPU）
    func processTextWithAI(inputText: String, systemPrompt: String) {
        let cleanInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanInput.isEmpty {
            self.updateAIProgressStatus("❌ 原始提取的文本为空，请先提取文本！")
            return
        }
        
        guard let url = URL(string: aiApiBaseUrl + "/chat/completions") else {
            self.updateAIProgressStatus("❌ 无效的 API 服务地址")
            return
        }
        
        // 强行关闭历史遗留任务，确保通道不发生叠加竞态
        cancelAIProcessing()
        
        isAIProcessing = true
        aiResultText = "" // 开启流式前，清空旧数据
        streamBuffer = Data() // 清空流式数据缓冲区
        aiTxtFileURL = nil // 清空上次导出的文件 URL 引用
        updateAIProgressStatus("本地 AI 正在推理润色，请耐心等待...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 86400.0 // 设定为 24 小时超长超时，使用户可以无限等待本地大模型生成
        
        if !aiApiKey.isEmpty {
            request.addValue("Bearer \(aiApiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": cleanInput]
        ]
        
        let requestBody: [String: Any] = [
            "model": aiSelectedModel.isEmpty ? "default" : aiSelectedModel,
            "messages": messages,
            "temperature": 0.1, // 低温度以保证极高字词还原度和纠错规范
            "stream": true // 开启流式传输！
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            self.updateAIProgressStatus("❌ 序列化请求失败")
            self.isAIProcessing = false
            return
        }
        
        // 创建一个单独的 URLSession，指定自己为 delegate 以便接收流式 SSE 分块数据
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        
        self.currentAISession = session
        self.currentAITask = task
        task.resume()
    }
    
    /// 主动中止并取消当前正在运行的本地 AI 文本净化请求
    func cancelAIProcessing() {
        streamBuffer = Data() // 主动取消时清空缓冲区
        if let task = currentAITask {
            task.cancel()
            currentAITask = nil
            
            currentAISession?.invalidateAndCancel()
            currentAISession = nil
            
            isAIProcessing = false
            updateAIProgressStatus("❌ 已主动取消 AI 优化净化流程。")
            logOutput += "\n[AI 提示] 用户主动取消了本地 AI 文本净化请求。\n"
        }
    }
    
    private func updateAIProgressStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.aiProgressStatus = status
        }
    }
    
    // 解析流式 Delta 返回值
    private func parseDeltaContent(from jsonStr: String) -> String? {
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }
    
    /// 【AI 净化文本自动保存】：将 AI 纠错净化完成后的文本自动写入本地同级目录下的 [原名]_AI净化.txt 文件
    private func saveAIResultToDisk() {
        guard let url = pdfURL, !aiResultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let baseName = url.deletingPathExtension().lastPathComponent
        let aiTxtURL = url.deletingLastPathComponent().appendingPathComponent(baseName + "_AI净化").appendingPathExtension("txt")
        
        do {
            try aiResultText.write(to: aiTxtURL, atomically: true, encoding: .utf8)
            self.updateAIProgressStatus("✅ 本地 AI 净化校对完成！已自动导出文件。")
            logOutput += "\n[AI 提示] 净化文本已成功自动保存至: \(aiTxtURL.lastPathComponent)\n"
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.aiTxtFileURL = aiTxtURL
            }
        } catch {
            self.updateAIProgressStatus("❌ 本地 AI 净化已完成，但自动写入硬盘失败: \(error.localizedDescription)")
            logOutput += "\n[AI 警告] 自动导出净化文件失败: \(error.localizedDescription)\n"
        }
    }
}

// MARK: - URLSessionDataDelegate 实现 (流式文本接收与按行分流解析)
extension PDFExtractorEngine: URLSessionDataDelegate {
    
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // 允许接收后续流数据包
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // 将新到的网络数据追加到流式数据缓冲区中，确保不会因为 TCP 分包截断导致 JSON 损坏或中文乱码
        streamBuffer.append(data)
        
        // 循环处理，直到 buffer 中没有换行符（ASCII 10）为止
        while let lineEndIndex = streamBuffer.firstIndex(of: 10) {
            // 提取出完整的一行数据
            let lineData = streamBuffer.subdata(in: 0..<lineEndIndex)
            // 从缓冲区中移除这部分数据，包括最后的换行符本身
            streamBuffer.removeSubrange(0...lineEndIndex)
            
            guard let lineStr = String(data: lineData, encoding: .utf8) else { continue }
            let trimmed = lineStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("data: ") {
                let jsonPart = trimmed.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
                if jsonPart == "[DONE]" {
                    continue
                }
                
                if let content = parseDeltaContent(from: jsonPart) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        // 实时流式追加内容，打字机回显！
                        self.aiResultText += content
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.streamBuffer = Data() // 清空流缓冲区
            self.isAIProcessing = false
            self.currentAITask = nil
            
            // 极其重要：显式释放 URLSession 以打断 delegate 引起的循环强引用内存泄漏
            self.currentAISession?.invalidateAndCancel()
            self.currentAISession = nil
            
            if let error = error as NSError? {
                if error.code == NSURLErrorCancelled {
                    // 主动取消，由于之前已经设置过状态，直接 return
                    return
                }
                self.updateAIProgressStatus("❌ 优化生成中断: \(error.localizedDescription)")
            } else {
                // 【自动保存机制】：AI 推理无错完美结束时，自动将其导出到本地
                self.saveAIResultToDisk()
            }
        }
    }
}

// MARK: - 支持的文字提取模式
enum ExtractionMode: String, CaseIterable, Identifiable {
    case smart = "智能提取（推荐）"
    case textOnly = "仅提取活字（极速）"
    case ocrOnly = "强制全部 OCR（适合扫描件）"
    
    var id: String { self.rawValue }
}

// MARK: - 毛玻璃效果视图 (macOS 原生毛玻璃窗口)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - 主界面视图
struct ContentView: View {
    @StateObject private var engine = PDFExtractorEngine()
    
    // UI 控制状态
    @State private var dragOver = false
    @State private var ignoreCase = true
    @State private var extractionMode: ExtractionMode = .smart
    @State private var eraseImageWatermark = false // 是否要在图片中白块擦除
    @State private var customWatermarks = ""
    @State private var resultText = ""
    @State private var txtFileURL: URL? = nil
    
    // 右侧标签卡片切换：0 -> 原始提取文本, 1 -> AI 优化文本
    @State private var selectedTab = 0
    
    // 折叠菜单展开管理
    @State private var isSettingsExpanded = true
    @State private var isWatermarkExpanded = true
    @State private var isAIExpanded = true
    
    // 高级 AI 优化与断行合并修复提示词
    @State private var systemPrompt = """
你是一个极为严谨的文本排版与错别字纠正助手。你将接收一段由 OCR 引擎从扫描件中识别出的原始文本。
请执行以下处理：
1. 保持原文的主体结构和逻辑含义完全不变，切勿重写、扩写或精简正文内容。
2. 修复文本中由于 OCR 识别误差导致的可能错字、别字（例如把“而且”识别为“面且”，把“我们”识别为“我门”）。
3. 智能修复不合理的强行换行与分段：OCR 识别出的每一行扫描文本经常有行尾生硬换行。你必须智能判断句意连贯性，对于本应是一个连贯句子的硬换行，应当将其合并拼接，并按照正常的自然段落进行排版，消除零碎的碎行和段落撕裂。
4. 【核心铁律】：每当你在排版、硬换行、字词上修改了任何内容，你必须在修改后的内容旁边，紧随其后附上大括号，格式为：“【识别是：[原始错误/硬换行]，修改为：[修改后/合并内容]】”。
例如：如果原文是“面且我门要\\n去公园”，纠正后应输出：“而且【识别是：面且，修改为：而且】我们【识别是：我门，修改为：我们】要去公园【识别是：要\\n去，修改为：要去】”。
5. 只输出处理纠正后的最终文本，严禁夹带任何多余的开场白、解释、Markdown 标记或总结语！
"""
    
    // 渐变背景配置
    let darkGradient = LinearGradient(
        colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // 【UI 性能卡死保护】：通过计算绑定限制在 TextEditor 内渲染的最大字数。真实的超长原始数据依然保存在变量中不受影响，复制和存盘均正常。
    private var previewTextBinding: Binding<String> {
        Binding(
            get: {
                if resultText.count > 15000 {
                    return String(resultText.prefix(15000)) + "\n\n【⚠️ 性能保护提示：文本总长度较大（当前共 \(resultText.count) 字），预览区已为您自动截断并展示前 15,000 字，以确保系统流畅。完整文本内容已自动安全保存在本地 TXT 文件夹内。】"
                }
                return resultText
            },
            set: { newValue in
                resultText = newValue
            }
        )
    }
    
    private var aiPreviewTextBinding: Binding<String> {
        Binding(
            get: {
                if engine.aiResultText.count > 15000 {
                    return String(engine.aiResultText.prefix(15000)) + "\n\n【⚠️ 性能保护提示：AI 生成结果过长（当前共 \(engine.aiResultText.count) 字），预览区已自动截断前 15,000 字以防渲染卡死。完整净化文本已安全写入本地。】"
                }
                return engine.aiResultText
            },
            set: { newValue in
                engine.aiResultText = newValue
            }
        )
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // ==================== 左侧控制侧边栏 ====================
            VStack(alignment: .leading, spacing: 0) {
                // 顶部标题
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PDF 本地去水印")
                            .font(.system(size: 16, weight: .bold))
                        Text("100% 离线文字提取与 AI 净化")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                Divider()
                    .padding(.horizontal, 16)
                
                // 设置滚动列表
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. 文件导入区域
                        if engine.pdfFileName.isEmpty {
                            DropZoneView(isDragOver: $dragOver) { url in
                                _ = engine.loadPDF(url: url)
                            }
                            .padding(.top, 10)
                        } else {
                            FileInfoView(
                                name: engine.pdfFileName,
                                size: engine.pdfFileSize,
                                pages: engine.pdfTotalPages,
                                onClear: {
                                    engine.clear()
                                    resultText = ""
                                    txtFileURL = nil
                                    selectedTab = 0
                                }
                            )
                            .padding(.top, 10)
                        }
                        
                        if !engine.pdfFileName.isEmpty {
                            // 2. 提取参数设置
                            VStack(alignment: .leading, spacing: 0) {
                                Button(action: { withAnimation { isSettingsExpanded.toggle() } }) {
                                    HStack {
                                        Text("提取设置")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Image(systemName: isSettingsExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                
                                if isSettingsExpanded {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Picker("提取模式", selection: $extractionMode) {
                                            ForEach(ExtractionMode.allCases) { mode in
                                                Text(mode.rawValue).tag(mode)
                                            }
                                        }
                                        .pickerStyle(.radioGroup)
                                        .horizontalRadioLayout()
                                        
                                        Toggle("忽略字母大小写", isOn: $ignoreCase)
                                            .toggleStyle(.checkbox)
                                        
                                        Toggle("擦除图片中的水印区域", isOn: $eraseImageWatermark)
                                            .toggleStyle(.checkbox)
                                        
                                        Text("💡 默认通过后处理技术无损净化水印，不伤正文。如果水印严重干扰识别，可开启上面选项进行像素擦除。")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineSpacing(2)
                                    }
                                    .padding(.top, 8)
                                    .padding(.bottom, 12)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .cornerRadius(12)
                            
                            // 3. 水印管理区域
                            VStack(alignment: .leading, spacing: 0) {
                                Button(action: { withAnimation { isWatermarkExpanded.toggle() } }) {
                                    HStack {
                                        Text("活字水印过滤管理")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Image(systemName: isWatermarkExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                
                                if isWatermarkExpanded {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if engine.watermarkCandidates.isEmpty {
                                            Text("未检测到高频活字水印。")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .padding(.vertical, 4)
                                        } else {
                                            Text("勾选要过滤的水印字词：")
                                                .font(.system(size: 10.5))
                                                .foregroundColor(.secondary)
                                            
                                            ForEach(0..<engine.watermarkCandidates.count, id: \.self) { idx in
                                                Toggle(isOn: $engine.watermarkCandidates[idx].isSelected) {
                                                    HStack {
                                                        Text(engine.watermarkCandidates[idx].text)
                                                            .font(.system(size: 11.5, weight: .medium))
                                                            .lineLimit(1)
                                                        Spacer()
                                                        Text("\(engine.watermarkCandidates[idx].occurrenceCount) 页")
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                .toggleStyle(.checkbox)
                                            }
                                        }
                                        
                                        Divider()
                                            .padding(.vertical, 4)
                                        
                                        Text("手动添加过滤词（逗号或换行隔开）:")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                        
                                        TextEditor(text: $customWatermarks)
                                            .font(.system(.body, design: .default))
                                            .frame(height: 50)
                                            .padding(4)
                                            .background(Color(nsColor: .textBackgroundColor))
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                            )
                                    }
                                    .padding(.top, 8)
                                    .padding(.bottom, 12)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .cornerRadius(12)
                            
                            // 4. 本地 AI 模块配置区域
                            VStack(alignment: .leading, spacing: 0) {
                                Button(action: { withAnimation { isAIExpanded.toggle() } }) {
                                    HStack {
                                        HStack(spacing: 6) {
                                            Image(systemName: "cpu.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.purple)
                                            Text("本地 AI 净化助手")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: isAIExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                
                                if isAIExpanded {
                                    VStack(alignment: .leading, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("API 服务地址:")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                            TextField("http://localhost:11434/v1", text: $engine.aiApiBaseUrl)
                                                .textFieldStyle(.roundedBorder)
                                                .disabled(engine.isAIProcessing) // 推理中禁用输入，防刷
                                            
                                            HStack(spacing: 8) {
                                                Button("Ollama") {
                                                    engine.aiApiBaseUrl = "http://localhost:11434/v1"
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                .disabled(engine.isAIProcessing)
                                                
                                                Button("LM Studio") {
                                                    engine.aiApiBaseUrl = "http://localhost:1234/v1"
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                .disabled(engine.isAIProcessing)
                                            }
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("AI 模型名称:")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                if engine.isAIFetchingModels {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                        .scaleEffect(0.6)
                                                }
                                            }
                                            
                                            if engine.aiModels.isEmpty {
                                                TextField("请输入模型 (如 qwen2.5-7b-instruct)", text: $engine.aiSelectedModel)
                                                    .textFieldStyle(.roundedBorder)
                                                    .disabled(engine.isAIProcessing)
                                            } else {
                                                Picker("选择模型", selection: $engine.aiSelectedModel) {
                                                    ForEach(engine.aiModels, id: \.self) { model in
                                                        Text(model).tag(model)
                                                    }
                                                }
                                                .pickerStyle(.menu)
                                                .labelsHidden()
                                                .disabled(engine.isAIProcessing)
                                            }
                                            
                                            Button(action: {
                                                engine.fetchAIModels()
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                    Text("获取本地可用模型")
                                                }
                                                .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .disabled(engine.isAIProcessing) // 【防重入锁】：AI运行时禁用网络刷新
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("排版与纠错系统提示词:")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                            TextEditor(text: $systemPrompt)
                                                .font(.system(size: 9.5))
                                                .frame(height: 70)
                                                .padding(3)
                                                .background(Color(nsColor: .textBackgroundColor))
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                                )
                                                .disabled(engine.isAIProcessing)
                                        }
                                        
                                        if !engine.aiProgressStatus.isEmpty {
                                            Text(engine.aiProgressStatus)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.purple)
                                                .lineLimit(2)
                                                .padding(.top, 2)
                                        }
                                    }
                                    .padding(.top, 8)
                                    .padding(.bottom, 12)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                
                Spacer()
                
                // 底部开始与净化操作大按钮 (包含重入防双击保护 .disabled)
                if !engine.pdfFileName.isEmpty && !engine.isProcessing {
                    VStack(spacing: 8) {
                        Button(action: {
                            let active = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
                            engine.extractText(
                                activeWatermarks: active,
                                customWatermarks: customWatermarks,
                                ignoreCase: ignoreCase,
                                mode: extractionMode,
                                eraseImageWatermark: eraseImageWatermark
                            ) { result, url in
                                self.resultText = result
                                self.txtFileURL = url
                                self.selectedTab = 0 // 回到原始文本
                            }
                        }) {
                            HStack(spacing: 8) {
                                if engine.isAnalyzingWatermarks {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.8)
                                        .brightness(0.5)
                                    Text("正在自动分析水印词...")
                                } else {
                                    Text("开始提取文字")
                                }
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                engine.isAnalyzingWatermarks ? 
                                AnyShapeStyle(Color.gray.opacity(0.4)) :
                                AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                            )
                            .cornerRadius(8)
                            .shadow(color: engine.isAnalyzingWatermarks ? Color.clear : Color.purple.opacity(0.2), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .disabled(engine.isAIProcessing || engine.isAnalyzingWatermarks) // AI 净化或水印分析运行时禁用提取按钮
                        
                        if !resultText.isEmpty && !engine.isAIProcessing {
                            Button(action: {
                                withAnimation {
                                    selectedTab = 1 // ✨【智能 Tab 跳转】：点击优化时，UI 自动跳往 AI 净化面板，展现打字机出字细节
                                }
                                engine.processTextWithAI(inputText: resultText, systemPrompt: systemPrompt)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                    Text("发送至本地 AI 净化")
                                }
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(8)
                                .shadow(color: Color.pink.opacity(0.25), radius: 5, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 400)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            
            // ==================== 右侧处理状态与结果展示区 ====================
            VStack(spacing: 0) {
                if engine.isProcessing {
                    // 原始文本提取中状态 (包含取消功能)
                    VStack(spacing: 24) {
                        Spacer()
                        
                        ProgressShimmerRing(progress: engine.progress)
                            .frame(width: 120, height: 120)
                        
                        VStack(spacing: 8) {
                            Text(engine.currentStatus)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("正在使用 Vision 本地引擎，请勿关闭应用")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        // 中止提取按钮
                        Button(action: {
                            engine.cancelPDFExtraction()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle")
                                Text("取消提取")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // 动态运行日志输出
                        ScrollView {
                            Text(engine.logOutput)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                                .lineSpacing(4)
                        }
                        .frame(width: 500, height: 180)
                        .padding(.top, 10)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !resultText.isEmpty {
                    // 重构的文本展示卡片区，双栏 Tab 视图
                    VStack(alignment: .leading, spacing: 0) {
                        // 1. 顶部自定义精美 TabBar 栏
                        HStack {
                            HStack(spacing: 4) {
                                Button(action: { selectedTab = 0 }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text")
                                        Text("原始提取文本")
                                    }
                                    .font(.system(size: 12.5, weight: selectedTab == 0 ? .bold : .medium))
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 14)
                                    .background(selectedTab == 0 ? Color.blue.opacity(0.15) : Color.clear)
                                    .foregroundColor(selectedTab == 0 ? .blue : .primary)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { selectedTab = 1 }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                        Text("本地 AI 纠错净化")
                                    }
                                    .font(.system(size: 12.5, weight: selectedTab == 1 ? .bold : .medium))
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 14)
                                    .background(selectedTab == 1 ? Color.purple.opacity(0.15) : Color.clear)
                                    .foregroundColor(selectedTab == 1 ? .purple : .primary)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(3)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            Spacer()
                            
                            // 右侧快捷复制操作 (真实的内存字符，无截断复制)
                            HStack(spacing: 10) {
                                if selectedTab == 0 {
                                    Button(action: {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.setString(resultText, forType: .string)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.on.doc")
                                            Text("复制原始")
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    if !engine.aiResultText.isEmpty {
                                        Button(action: {
                                            let pasteboard = NSPasteboard.general
                                            pasteboard.clearContents()
                                            pasteboard.setString(engine.aiResultText, forType: .string)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "doc.on.doc")
                                                Text("复制净化文本")
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.purple.opacity(0.15))
                                            .foregroundColor(.purple)
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                        
                        // 分割线
                        Divider()
                            .padding(.horizontal, 24)
                        
                        // 2. 醒目的高亮横幅提示 (Banner，支持 Finder 点击直达高亮定位)
                        if selectedTab == 0 {
                            if let url = txtFileURL {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 13, weight: .bold))
                                    Text("🎉 文字提取已完成！已自动导出原始文本至: ")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.primary)
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(.green)
                                        .underline()
                                        .onTapGesture {
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        }
                                        .help("点击在 Finder 中定位该文件")
                                    Spacer()
                                }
                                .padding(.vertical, 9)
                                .padding(.horizontal, 14)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.green.opacity(0.25), lineWidth: 1)
                                )
                                .padding(.horizontal, 24)
                                .padding(.top, 14)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        } else {
                            if let url = engine.aiTxtFileURL {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.purple)
                                        .font(.system(size: 13, weight: .bold))
                                    Text("✨ AI 优化已完成！已自动导出净化文本至: ")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.primary)
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(.purple)
                                        .underline()
                                        .onTapGesture {
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        }
                                        .help("点击在 Finder 中定位该文件")
                                    Spacer()
                                }
                                .padding(.vertical, 9)
                                .padding(.horizontal, 14)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                                )
                                .padding(.horizontal, 24)
                                .padding(.top, 14)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        
                        // Tab 内容区域 (带有大文件渲染保护，防止卡死 UI)
                        if selectedTab == 0 {
                            TextEditor(text: previewTextBinding)
                                .font(.system(.body, design: .default))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(8)
                                .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 20)
                        } else {
                            // AI Tab 内容
                            if engine.isAIProcessing {
                                VStack(spacing: 24) {
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.large)
                                    
                                    VStack(spacing: 8) {
                                        Text("本地 AI 正在推理润色...")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(engine.aiProgressStatus)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 40)
                                    }
                                    
                                    // 精致的取消按钮
                                    Button(action: {
                                        engine.cancelAIProcessing()
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "xmark.circle")
                                            Text("取消优化")
                                        }
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.red)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if !engine.aiResultText.isEmpty {
                                // 展示 AI 纠错净化文本
                                TextEditor(text: aiPreviewTextBinding)
                                    .font(.system(.body, design: .default))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(8)
                                    .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 20)
                            } else {
                                // AI 未开始的空白引导状态
                                VStack(spacing: 16) {
                                    Spacer()
                                    
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 48))
                                        .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                                    
                                    Text("本地 AI 文本净化")
                                        .font(.system(size: 15, weight: .bold))
                                    
                                    Text("本地 AI 可以智能修复 OCR 扫描产生的错别字，并合并因为换行生硬造成的生硬断行。\n所有的修改都会使用【大括号对】标出，确保可读可查。")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(4)
                                        .padding(.horizontal, 50)
                                    
                                    Button(action: {
                                        withAnimation {
                                            selectedTab = 1
                                        }
                                        engine.processTextWithAI(inputText: resultText, systemPrompt: systemPrompt)
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "sparkles")
                                            Text("一键开始本地 AI 净化")
                                        }
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 9)
                                        .padding(.horizontal, 24)
                                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if !engine.aiProgressStatus.isEmpty {
                                        Text(engine.aiProgressStatus)
                                            .font(.system(size: 11))
                                            .foregroundColor(.purple)
                                    }
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 欢迎/空状态
                    VStack(spacing: 18) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                        
                        Text("暂无处理内容")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Text("请在左侧导入 PDF 文件并完成水印配置")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(darkGradient)
        }
        .environment(\.colorScheme, .dark) // 默认使用更具科技感和高端视觉的深色模式
    }
}

// MARK: - 拖拽导入虚线框视图
struct DropZoneView: View {
    @Binding var isDragOver: Bool
    var onFileDropped: (URL) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(isDragOver ? .purple : .secondary)
                .scaleEffect(isDragOver ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragOver)
            
            VStack(spacing: 6) {
                Text("拖入 PDF 文件到此区域")
                    .font(.system(size: 13, weight: .semibold))
                Text("或者点击浏览文件")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDragOver ? Color.purple : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 10, dash: [6, 4], dashPhase: 0))
                .background(isDragOver ? Color.purple.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.pdf]
            if panel.runModal() == .OK, let url = panel.url {
                onFileDropped(url)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url = url, url.pathExtension.lowercased() == "pdf" {
                    DispatchQueue.main.async {
                        onFileDropped(url)
                    }
                }
            }
            return true
        }
    }
}

// MARK: - 文件信息卡片视图
struct FileInfoView: View {
    let name: String
    let size: String
    let pages: Int
    var onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.red")
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    
                    Text("\(size)  •  共 \(pages) 页")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - 包含流光质感的圆形进度条
struct ProgressShimmerRing: View {
    let progress: Double
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // 背景圆环
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 10)
            
            // 进度条（带渐变）
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    LinearGradient(colors: [.purple, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(Angle(degrees: -90))
                .animation(.linear(duration: 0.2), value: progress)
            
            // 进度百分比文本
            VStack(spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("提取进度")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - SwiftUI RadioButton picker layout helper
extension View {
    func horizontalRadioLayout() -> some View {
        self.modifier(HorizontalRadioStyleModifier())
    }
}

struct HorizontalRadioStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .labelsHidden()
            .padding(.vertical, 4)
    }
}
