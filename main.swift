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
                .frame(minWidth: 960, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar) // 隐藏标题栏，使 UI 更一体化、现代化
    }
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
        
        self.logOutput = "文件成功加载: \(url.lastPathComponent)\n"
        self.currentStatus = "就绪，正在自动分析水印词..."
        
        // 自动分析疑似水印
        analyzeWatermarks(doc)
        return true
    }
    
    /// 清除当前加载的文件
    func clear() {
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
    }
    
    /// 扫描 PDF 的前若干页，统计高频出现的疑似水印文字
    private func analyzeWatermarks(_ doc: PDFDocument) {
        var counts: [String: Int] = [:]
        let pageCount = doc.pageCount
        let maxPagesToScan = min(pageCount, 30) // 最多扫描前30页用于水印分析，避免大文件卡顿
        
        for i in 0..<maxPagesToScan {
            guard let page = doc.page(at: i) else { continue }
            let selections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
            for sel in selections {
                if let text = sel.string?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !text.isEmpty {
                    // 水印字数通常在这个范围，且不至于是一整段话
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
        
        DispatchQueue.main.async {
            self.watermarkCandidates = candidates
            if candidates.isEmpty {
                self.currentStatus = "分析完毕，未检测到高频活字水印。"
                self.logOutput += "未检测到明显的页面重复活字水印，您也可以手动添加过滤词。\n"
            } else {
                self.currentStatus = "分析完毕，发现 \(candidates.count) 个疑似水印词。"
                self.logOutput += "检测到疑似水印词：\n" + candidates.map { " - \"\($0.text)\" (\($0.occurrenceCount)页出现)" }.joined(separator: "\n") + "\n"
            }
        }
    }
    
    /// 执行文字提取与去水印任务
    func extractText(
        activeWatermarks: Set<String>,
        customWatermarks: String,
        ignoreCase: Bool,
        mode: ExtractionMode,
        eraseImageWatermark: Bool,
        completion: @escaping (String, URL?) -> Void
    ) {
        guard let doc = pdfDocument, let url = pdfURL else { return }
        
        isProcessing = true
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            let totalPages = doc.pageCount
            var finalResult = ""
            
            for i in 0..<totalPages {
                let pageIndex = i + 1
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
                
                finalResult += "\n[第 \(pageIndex) 页]\n"
                finalResult += pageText + "\n"
                
                self.updateProgress(Double(pageIndex) / Double(totalPages))
            }
            
            // 写入本地同名 TXT 文件
            let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
            do {
                try finalResult.write(to: txtURL, atomically: true, encoding: .utf8)
                self.updateStatus("🎉 处理完成！结果已成功保存到: \(txtURL.lastPathComponent)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(finalResult, txtURL)
                }
            } catch {
                self.updateStatus("❌ 保存文件失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(finalResult, nil)
                }
            }
        }
    }
    
    private func updateStatus(_ status: String) {
        DispatchQueue.main.async {
            self.currentStatus = status
            self.logOutput += status + "\n"
        }
    }
    
    private func updateProgress(_ val: Double) {
        DispatchQueue.main.async {
            self.progress = val
        }
    }
    
    /// 处理单个页面，根据模式决定是直接提取活字还是执行 OCR
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
            pageResult = normalTextPieces.joined(separator: "\n")
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
    
    /// 文本后处理：在识别好的文字中精准剔除水印字词
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
        
        // 清理由于剔除而形成的多余空行
        let lines = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return lines.joined(separator: "\n")
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
        
        // 2. 缩放坐标系，以便直接用 PDFKit 原生坐标进行绘制
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        
        // 3. 绘制 PDF 页面
        page.draw(with: .mediaBox, to: context.cgContext)
        
        // 4. 水印擦除：用白色填充水印 selections 的 bounds。
        // PDFSelection 是一行行的，对于倾斜水印，selectionsByLine 会把它分割为精细的单行/断行，覆盖它的 bounds 伤及正文的区域极其微小。
        NSColor.white.set()
        for selection in watermarkSelections {
            let bounds = selection.bounds(for: page)
            // 向外微调 1.5 个像素，防止由于抗锯齿边缘而出现文字的笔画残留阴影，干扰 OCR
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
    @State private var eraseImageWatermark = false // 是否要在图片中白块擦除，默认通过文本后处理过滤，安全不伤正文
    @State private var customWatermarks = ""
    @State private var resultText = ""
    @State private var txtFileURL: URL? = nil
    
    // 渐变背景配色
    let purpleGrad = LinearGradient(
        colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        HStack(spacing: 0) {
            // ==================== 左侧控制侧边栏 ====================
            VStack(alignment: .leading, spacing: 20) {
                // 顶部标题
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PDF 本地去水印")
                            .font(.system(size: 16, weight: .bold))
                        Text("100% 离线文字提取工具")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                
                Divider()
                    .padding(.horizontal, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // 1. 文件导入区域
                        if engine.pdfFileName.isEmpty {
                            DropZoneView(isDragOver: $dragOver) { url in
                                _ = engine.loadPDF(url: url)
                            }
                        } else {
                            FileInfoView(
                                name: engine.pdfFileName,
                                size: engine.pdfFileSize,
                                pages: engine.pdfTotalPages,
                                onClear: {
                                    engine.clear()
                                    resultText = ""
                                    txtFileURL = nil
                                }
                            )
                        }
                        
                        if !engine.pdfFileName.isEmpty {
                            // 2. 提取参数设置
                            VStack(alignment: .leading, spacing: 12) {
                                Text("提取设置")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
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
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                            }
                            .padding(14)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .cornerRadius(12)
                            
                            // 3. 水印管理区域
                            VStack(alignment: .leading, spacing: 12) {
                                Text("活字水印过滤管理")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                if engine.watermarkCandidates.isEmpty {
                                    Text("未检测到高频活字水印。")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 4)
                                } else {
                                    Text("检测到以下疑似水印词（已默认勾选）：")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(0..<engine.watermarkCandidates.count, id: \.self) { idx in
                                        Toggle(isOn: $engine.watermarkCandidates[idx].isSelected) {
                                            HStack {
                                                Text(engine.watermarkCandidates[idx].text)
                                                    .font(.system(size: 12, weight: .medium))
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
                                
                                Text("自定义过滤词（用逗号或回车分隔）:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $customWatermarks)
                                    .font(.system(size: 11))
                                    .frame(height: 50)
                                    .padding(4)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .padding(14)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                
                Spacer()
                
                // 底部开始按钮
                if !engine.pdfFileName.isEmpty && !engine.isProcessing {
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
                        }
                    }) {
                        Text("开始提取文字")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(8)
                            .shadow(color: Color.purple.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 380)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            
            // ==================== 右侧处理状态与结果展示区 ====================
            VStack(spacing: 0) {
                if engine.isProcessing {
                    // 处理中状态
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
                        .frame(width: 480, height: 180)
                        .padding(.top, 10)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !resultText.isEmpty {
                    // 处理完成后的结果展示区
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("提取文字预览")
                                    .font(.system(size: 16, weight: .bold))
                                if let url = txtFileURL {
                                    Text("已保存至: \(url.path)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 10) {
                                Button(action: {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(resultText, forType: .string)
                                    // 显示一个小 Toast 或是修改按钮文字，这里直接用状态做提示
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("复制全部")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                
                                if let url = txtFileURL {
                                    Button(action: {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder")
                                            Text("在 Finder 中显示")
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.purple.opacity(0.1))
                                        .foregroundColor(.purple)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        
                        Divider()
                            .padding(.horizontal, 24)
                        
                        TextEditor(text: $resultText)
                            .font(.system(.body, design: .default))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
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
            .background(purpleGrad)
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
        .frame(height: 160)
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
        .padding(14)
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
