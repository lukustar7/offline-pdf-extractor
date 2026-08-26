import SwiftUI

// MARK: - 主容器视图 (macOS 原生工作台架构)
struct ContentView: View {
    @StateObject private var engine = PDFExtractorEngine()
    @ObservedObject var aiEngine: AIProcessingEngine
    
    // 左右侧栏折叠状态控制 (持久化保存用户视口偏好)
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showInspector") private var showInspector = true
    
    // 首次启动欢迎弹窗状态
    @AppStorage("hasShownWelcomeSheet") private var hasShownWelcomeSheet = false
    
    // 提取范围模式
    @AppStorage("pageRangeMode") private var pageRangeMode = 0
    @AppStorage("pageRangeString") private var pageRangeString = ""
    
    var body: some View {
        ZStack {
            if engine.pdfDocument == nil {
                // 1. 文件尚未加载时，全屏展示极简拖拽/待机导入页
                LaunchView(
                    errorMessage: engine.errorMessage,
                    onFileSelected: { url in
                        loadPDF(url)
                    },
                    onInvalidFile: { errorMsg in
                        engine.errorMessage = errorMsg
                    }
                )
                .transition(.opacity)
            } else {
                // 2. 文件载入完成后，展示可折叠的 页面缩略图侧栏 + PDF 画布 + 结果检查器 原生工作台。
                HSplitView {
                    if showSidebar {
                        SidebarThumbnailView(engine: engine)
                            .frame(minWidth: 130, idealWidth: 160, maxWidth: 220)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    
                    HSplitView {
                        PDFCanvasView(
                            engine: engine,
                            currentPage: $engine.currentPage
                        )
                        .frame(minWidth: 400, idealWidth: 700, maxWidth: .infinity)
                        
                        if showInspector {
                            ResultInspectorView(
                                engine: engine,
                                aiEngine: aiEngine,
                                currentPage: $engine.currentPage,
                                onStartExtraction: startExtractionAction
                            )
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(minWidth: 400, maxWidth: .infinity)
                }
                .transition(.opacity)
            }
        }
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        .sheet(isPresented: $engine.showWelcomeSheet) {
            WelcomeView()
        }
        .onAppear {
            if !hasShownWelcomeSheet {
                engine.showWelcomeSheet = true
            }
        }
        // 挂载 macOS 顶级 Window 工具栏支持，提供全键盘快捷键与折叠工作流
        .toolbar {
            // 1. 左侧：侧边栏折叠按钮
            ToolbarItemGroup(placement: .navigation) {
                if engine.pdfDocument != nil {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.leading")
                    }
                    .help(showSidebar ? "收起页面缩略图 (⌘⌥S)" : "展开页面缩略图 (⌘⌥S)")
                    .keyboardShortcut("s", modifiers: [.command, .option])
                }
            }
            
            // 2. 中间：全局页码联动翻页与回车跳转控制组
            ToolbarItemGroup(placement: .principal) {
                if engine.pdfTotalPages > 0 {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button(action: {
                            if engine.currentPage > 1 {
                                engine.currentPage -= 1
                            }
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(engine.currentPage <= 1 || engine.isProcessing)
                        .help("上一页")
                        
                        TextField("", text: $engine.pageInput, onCommit: {
                            if let newPage = Int(engine.pageInput.trimmingCharacters(in: .whitespacesAndNewlines)),
                               newPage >= 1 && newPage <= engine.pdfTotalPages {
                                engine.currentPage = newPage
                            } else {
                                engine.pageInput = String(engine.currentPage)
                            }
                        })
                        .frame(width: 44)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .disabled(engine.isProcessing)
                        .help("输入页码回车跳转")
                        
                        Text("/  \(engine.pdfTotalPages) 页")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        
                        Button(action: {
                            if engine.currentPage < engine.pdfTotalPages {
                                engine.currentPage += 1
                            }
                        }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(engine.currentPage >= engine.pdfTotalPages || engine.isProcessing)
                        .help("下一页")
                    }
                }
            }
            
            // 3. 右侧：操作按钮与检查器折叠
            ToolbarItemGroup(placement: .primaryAction) {
                if engine.pdfFileName.isEmpty {
                    Button(action: openFileAction) {
                        Label("导入 PDF", systemImage: "doc.badge.plus")
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("导入 PDF 文件并自动分析 (⌘O)")
                } else {
                    Button(action: openFileAction) {
                        Label("更换文件", systemImage: "doc.badge.plus")
                    }
                    .help("导入另一个 PDF 文档 (⌘O)")
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showInspector.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help(showInspector ? "收起结果检查器 (⌘⌥I)" : "展开结果检查器 (⌘⌥I)")
                    .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
        }
        .onChange(of: engine.currentPage) { oldValue, newValue in
            engine.pageInput = String(newValue)
            engine.preloadThumbnailsAround(pageNumber: newValue)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowWelcomeSheetNotification"))) { _ in
            engine.showWelcomeSheet = true
        }
        .onDisappear {
            engine.cancelPDFExtraction(showStatus: false)
            aiEngine.cancelAIProcessing(showStatus: false)
        }
    }
    
    /// 导入文件
    private func openFileAction() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            loadPDF(url)
        }
    }

    /// 所有导入入口统一经过这里
    private func loadPDF(_ url: URL) {
        aiEngine.cancelAIProcessing(showStatus: false)
        aiEngine.clear()
        engine.loadPDF(url: url)
    }
    
    /// 触发物理分段提取文字
    private func startExtractionAction() {
        let active = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
        let customWatermarks = UserDefaults.standard.string(forKey: "customWatermarks") ?? ""
        let ignoreCase = UserDefaults.standard.object(forKey: "ignoreCase") as? Bool ?? true
        
        let targetRangeString: String
        if pageRangeMode == 1 {
            targetRangeString = "\(engine.currentPage)"
        } else if pageRangeMode == 2 {
            targetRangeString = pageRangeString
        } else {
            targetRangeString = ""
        }
        
        let scenarioRaw = UserDefaults.standard.string(forKey: "processingScenario") ?? PDFProcessingScenario.electronicTextWithTextWatermark.rawValue
        let scenario = PDFProcessingScenario(rawValue: scenarioRaw) ?? .electronicTextWithTextWatermark
        let eraseImageWatermark = UserDefaults.standard.object(forKey: "eraseImageWatermark") as? Bool ?? false
        let removeLightWatermarks = UserDefaults.standard.object(forKey: "removeLightWatermarks") as? Bool ?? true
        let removeColorStamps = UserDefaults.standard.object(forKey: "removeColorStamps") as? Bool ?? false

        do {
            let request = try PDFExtractionRequest(
                scenario: scenario,
                activeWatermarks: active,
                customWatermarks: customWatermarks,
                ignoreCase: ignoreCase,
                eraseImageWatermark: eraseImageWatermark,
                removeLightWatermarks: removeLightWatermarks,
                removeColorStamps: removeColorStamps,
                pageRangeString: targetRangeString,
                maximumPageCount: engine.pdfTotalPages
            )
            engine.currentPage = request.targetPages.first ?? 1
            engine.extractText(request: request)
        } catch {
            engine.errorMessage = error.localizedDescription
        }
    }
    
    /// 触发物理分段 AI 净化
    private func startAIProcessingAction() {
        let showChanges = UserDefaults.standard.bool(forKey: "aiShowChanges")
        let passWatermarks = UserDefaults.standard.bool(forKey: "aiPassWatermarks")
        let active = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
        let customWatermarks = UserDefaults.standard.string(forKey: "customWatermarks") ?? ""
        let storedPrompt = AIPromptBuilder.storedSystemPrompt()
        let finalPrompt = AIPromptBuilder.composedPrompt(
            basePrompt: storedPrompt,
            showChanges: showChanges,
            passWatermarks: passWatermarks,
            activeWatermarks: active,
            customWatermarks: customWatermarks
        )
        
        aiEngine.processTextWithAI(
            extractedPages: engine.extractedPagesText,
            targetPages: engine.extractedPagesText.keys.sorted(),
            systemPrompt: finalPrompt
        )
    }
}

#if canImport(PreviewsMacros)
#Preview {
    ContentView(aiEngine: AIProcessingEngine())
        .frame(minWidth: 1_000, minHeight: 700)
}
#endif
