import SwiftUI

// MARK: - 主容器视图 (四栏并排物理页码联动架构)
struct ContentView: View {
    @StateObject private var engine = PDFExtractorEngine()
    @StateObject private var aiEngine = AIProcessingEngine()
    
    // 原始提取全文暂存（用于支持历史导出/高亮）
    @State private var resultText = ""
    @State private var txtFileURL: URL? = nil
    @State private var mdFileURL: URL? = nil
    
    // 当前工作区所处的 Tab 标识（兼容旧菜单通知）
    @State private var selectedTab = 0
    
    // 全局物理页码联动状态，作为共享单一事实源驱动后三栏（PDF预览、原文识字、AI优化）
    @State private var currentPage = 1
    
    var body: some View {
        ZStack {
            if engine.pdfDocument == nil {
                // 1. 文件尚未加载时，全屏展示极简拖拽/导入页
                LaunchView(
                    onFileSelected: { url in
                        currentPage = 1
                        engine.loadPDF(url: url)
                    },
                    onInvalidFile: { errorMsg in
                        engine.errorMessage = errorMsg
                    }
                )
                .transition(.opacity)
            } else {
                // 2. 文件载入完成后，平滑展示全新的“四栏并排物理页码联动工作区”
                HSplitView {
                    // 第一栏：配置控制侧边栏
                    SidebarView(
                        engine: engine,
                        aiEngine: aiEngine,
                        resultText: $resultText,
                        txtFileURL: $txtFileURL,
                        mdFileURL: $mdFileURL,
                        selectedTab: $selectedTab
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                    
                    // 第二栏：PDF 原件预览区
                    PDFPreviewView(
                        pdfDocument: engine.pdfDocument,
                        currentPage: $currentPage
                    )
                    .frame(minWidth: 240, idealWidth: 340, maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.2))
                    
                    // 第三栏：中部原始识字区
                    RawTextColumn(
                        engine: engine,
                        currentPage: $currentPage,
                        onStartExtraction: startExtractionAction
                    )
                    .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity)
                    
                    // 第四栏：右侧 AI 优化净化区
                    AITextColumn(
                        aiEngine: aiEngine,
                        extractorEngine: engine,
                        currentPage: $currentPage
                    )
                    .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity)
                }
                .transition(.opacity)
            }
        }
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        // 挂载 macOS 顶级 Window 工具栏支持，提供全键盘快捷键工作流
        .toolbar {
            // 1. 折叠左侧栏按钮
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
                .help("显示或折叠左侧配置面板")
            }
            
            // 2. 核心文件导入/关闭控制
            ToolbarItem(placement: .primaryAction) {
                if engine.pdfFileName.isEmpty {
                    Button(action: openFileAction) {
                        Label("导入 PDF", systemImage: "doc.badge.plus")
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("导入 PDF 文件并自动分析 (⌘O)")
                } else {
                    Button(action: clearFileAction) {
                        Label("关闭文件", systemImage: "xmark.circle")
                    }
                    .help("清除当前加载的文件及元数据")
                }
            }
            
            // 5. Finder 路径直达
            if let url = txtFileURL {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }) {
                        Image(systemName: "folder")
                    }
                    .help("在 Finder 中打开并定位已生成的文本文件")
                }
            }
        }
        // 响应菜单/通知广播
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenFileNotification"))) { _ in
            openFileAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartExtractionNotification"))) { _ in
            if !engine.pdfFileName.isEmpty && !engine.isProcessing && !aiEngine.isAIProcessing && !engine.isAnalyzingWatermarks {
                startExtractionAction()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartAINotification"))) { _ in
            if !engine.extractedPagesText.isEmpty && !aiEngine.isAIProcessing && !engine.isProcessing {
                startAIProcessingAction()
            }
        }
    }
    
    /// 折叠侧边栏
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    
    /// 导入文件
    private func openFileAction() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            currentPage = 1
            engine.loadPDF(url: url)
        }
    }
    
    /// 关闭当前 PDF 并且清空引擎的所有物理缓存
    private func clearFileAction() {
        engine.clear()
        aiEngine.clear()
        resultText = ""
        txtFileURL = nil
        mdFileURL = nil
        currentPage = 1
    }
    
    /// 触发物理分段提取文字
    private func startExtractionAction() {
        let active = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
        let customWatermarks = UserDefaults.standard.string(forKey: "customWatermarks") ?? ""
        let ignoreCase = UserDefaults.standard.object(forKey: "ignoreCase") as? Bool ?? true
        let eraseImageWatermark = UserDefaults.standard.object(forKey: "eraseImageWatermark") as? Bool ?? false
        let pageRangeString = UserDefaults.standard.string(forKey: "pageRangeString") ?? ""
        
        let modeRaw = UserDefaults.standard.string(forKey: "extractionMode") ?? ExtractionMode.smart.rawValue
        let mode = ExtractionMode(rawValue: modeRaw) ?? .smart
        let watermarkRemovalModeRaw = UserDefaults.standard.string(forKey: "watermarkRemovalMode") ?? WatermarkRemovalMode.auto.rawValue
        let watermarkRemovalMode = WatermarkRemovalMode(rawValue: watermarkRemovalModeRaw) ?? .auto
        let enableWatermarkFilter = UserDefaults.standard.object(forKey: "enableWatermarkFilter") as? Bool ?? true
        
        currentPage = 1
        
        engine.extractText(
            activeWatermarks: active,
            customWatermarks: customWatermarks,
            ignoreCase: ignoreCase,
            mode: mode,
            watermarkRemovalMode: watermarkRemovalMode,
            enableWatermarkFilter: enableWatermarkFilter,
            eraseImageWatermark: eraseImageWatermark,
            pageRangeString: pageRangeString
        ) { result, url, mdUrl, avgTime in
            self.resultText = result
            self.txtFileURL = url
            self.mdFileURL = mdUrl
        }
    }
    
    /// 触发物理分段 AI 净化
    private func startAIProcessingAction() {
        let systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? ""
        
        let active = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
        let customWatermarks = UserDefaults.standard.string(forKey: "customWatermarks") ?? ""
        let customList = customWatermarks
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let allWatermarks = active.union(customList)
        
        var finalPrompt = systemPrompt
        if !allWatermarks.isEmpty {
            let watermarkStr = allWatermarks.sorted().joined(separator: ", ")
            finalPrompt += "\n\n【参考提示——已知页面残余干扰词】：\(watermarkStr)\n如果输入正文的段落间或句子中，出现了与这些干扰词相关的无意义残留、乱码或碎裂的字符碎片，请在净化时将其作为噪音滤除；但如果该字词在上下文中属于正常的正文句子组成部分且语义连贯，请务必保留，切勿误伤正文。"
        }
        
        aiEngine.processTextWithAI(
            extractedPages: engine.extractedPagesText,
            targetPages: Array(1...engine.pdfTotalPages),
            systemPrompt: finalPrompt,
            fileURL: engine.pdfURL
        )
    }
}
