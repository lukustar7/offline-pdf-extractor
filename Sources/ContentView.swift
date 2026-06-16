import SwiftUI

// MARK: - 主容器视图
struct ContentView: View {
    @StateObject private var engine = PDFExtractorEngine()
    @StateObject private var aiEngine = AIProcessingEngine()
    
    @State private var resultText = ""
    @State private var txtFileURL: URL? = nil
    @State private var mdFileURL: URL? = nil
    
    // selectedTab: 0 -> 原始提取文本, 1 -> 本地 AI 纠错净化
    @State private var selectedTab = 0
    
    var body: some View {
        HSplitView {
            // 左侧控制区 (Form 配置参数)
            SidebarView(
                engine: engine,
                aiEngine: aiEngine,
                resultText: $resultText,
                txtFileURL: $txtFileURL,
                mdFileURL: $mdFileURL,
                selectedTab: $selectedTab
            )
            // 彻底移除固定 frame 宽，允许 macOS 原生 Split 拖拽拉伸
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 450)
            
            // 右侧主展示对照区
            ResultView(
                engine: engine,
                aiEngine: aiEngine,
                resultText: $resultText,
                txtFileURL: $txtFileURL,
                mdFileURL: $mdFileURL,
                selectedTab: $selectedTab
            )
            .frame(minWidth: 500, maxWidth: .infinity)
        }
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        // 挂载 macOS 官方推荐的顶级 Window 工具栏 (Toolbar)
        .toolbar {
            // 1. 折叠左侧栏的导航按钮
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
                .help("显示或折叠左侧提取配置面板")
            }
            
            // 2. 核心文件导入/关闭控制
            ToolbarItem(placement: .primaryAction) {
                if engine.pdfFileName.isEmpty {
                    Button(action: openFileAction) {
                        Label("导入 PDF", systemImage: "doc.badge.plus")
                    }
                    .keyboardShortcut("o", modifiers: .command) // 直接在可见按钮上绑定快捷键 (P3-8 修复)
                    .help("导入 PDF 文件并自动分析 (⌘O)")
                } else {
                    Button(action: clearFileAction) {
                        Label("关闭文件", systemImage: "xmark.circle")
                    }
                    .help("清除当前加载的文件及元数据")
                }
            }
            
            // 3. 核心提取/取消提取指令
            if !engine.pdfFileName.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    if engine.isProcessing {
                        Button(action: { engine.cancelPDFExtraction() }) {
                            Label("停止提取", systemImage: "stop.circle")
                                .foregroundColor(.red)
                        }
                        .help("中止当前的文本提取线程")
                    } else {
                        // macOS 最新设计语言：在按钮点击/触发提取时增加弹性物理弹跳动画反馈 (Symbol Effects)
                        if #available(macOS 14.0, *) {
                            Button(action: startExtractionAction) {
                                Label("提取文字", systemImage: "play.fill")
                            }
                            .symbolEffect(.bounce, value: engine.isProcessing)
                            .disabled(aiEngine.isAIProcessing || engine.isAnalyzingWatermarks)
                            .keyboardShortcut("r", modifiers: .command)
                            .help("执行本地文字提取与去水印 (⌘R)")
                        } else {
                            Button(action: startExtractionAction) {
                                Label("提取文字", systemImage: "play.fill")
                            }
                            .disabled(aiEngine.isAIProcessing || engine.isAnalyzingWatermarks)
                            .keyboardShortcut("r", modifiers: .command)
                            .help("执行本地文字提取与去水印 (⌘R)")
                        }
                    }
                }
            }
            
            // 4. AI 净化控制
            if !resultText.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    if aiEngine.isAIProcessing {
                        Button(action: { aiEngine.cancelAIProcessing() }) {
                            Label("停止 AI", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        .help("中止当前的本地 AI 净化校对")
                    } else {
                        // macOS 最新设计语言：在 AI 净化触发时增加 sparkles 图标弹性弹跳效果，极具灵动感
                        if #available(macOS 14.0, *) {
                            Button(action: startAIProcessingAction) {
                                Label("AI 净化", systemImage: "sparkles")
                            }
                            .symbolEffect(.bounce, value: aiEngine.isAIProcessing)
                            .help("发送已提取文本进行本地 AI 排版与纠错")
                        } else {
                            Button(action: startAIProcessingAction) {
                                Label("AI 净化", systemImage: "sparkles")
                            }
                            .help("发送已提取文本进行本地 AI 排版与纠错")
                        }
                    }
                }
            }
            
            // 5. 快速在 Finder 中高亮物理文件
            if let url = txtFileURL {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }) {
                        Image(systemName: "folder")
                    }
                    .help("在 Finder 中打开并定位已生成的文本文件")
                }
            }
        }
        // 核心差距 A 修复：挂载通知中心监听器，响应来自系统菜单栏（Menu Bar Commands）的触发，保障键盘工作流
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenFileNotification"))) { _ in
            openFileAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartExtractionNotification"))) { _ in
            if !engine.pdfFileName.isEmpty && !engine.isProcessing && !aiEngine.isAIProcessing && !engine.isAnalyzingWatermarks {
                startExtractionAction()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartAINotification"))) { _ in
            if !resultText.isEmpty && !aiEngine.isAIProcessing && !engine.isProcessing {
                startAIProcessingAction()
            }
        }
    }
    
    /// 触发 macOS 系统原生的 NSSplitViewController 侧边栏折叠机制
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    
    /// 打开 PDF 逻辑
    private func openFileAction() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            engine.loadPDF(url: url)
        }
    }
    
    /// 关闭文件与重置
    private func clearFileAction() {
        engine.clear()
        resultText = ""
        txtFileURL = nil
        mdFileURL = nil
        selectedTab = 0
    }
    
    /// 开始提取文本
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
            withAnimation {
                self.selectedTab = 1 // 跳转至提取文本 Tab (由 0 改为 1)
            }
        }
    }
    
    /// 发送给 AI 纠错净化
    private func startAIProcessingAction() {
        withAnimation {
            self.selectedTab = 2 // 跳转至 AI Tab (由 1 改为 2)
        }
        let systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? ""
        aiEngine.processTextWithAI(
            inputText: resultText,
            systemPrompt: systemPrompt,
            fileURL: engine.pdfURL
        )
    }
}
