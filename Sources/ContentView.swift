import SwiftUI

// MARK: - 主容器视图 (macOS 工作台架构)
struct ContentView: View {
    @StateObject private var engine = PDFExtractorEngine()
    @StateObject private var aiEngine = AIProcessingEngine()
    
    // 全局物理页码联动状态，作为 PDF 画布与右侧结果检查器的单一事实源。
    @State private var currentPage = 1
    @State private var pageInput = "1"
    
    var body: some View {
        ZStack {
            if engine.pdfDocument == nil {
                // 1. 文件尚未加载时，全屏展示极简拖拽/导入页
                LaunchView(
                    onFileSelected: { url in
                        currentPage = 1
                        pageInput = "1"
                        engine.loadPDF(url: url)
                    },
                    onInvalidFile: { errorMsg in
                        engine.errorMessage = errorMsg
                    }
                )
                .transition(.opacity)
            } else {
                // 2. 文件载入完成后，展示 Sidebar + PDF Canvas + Inspector 工作台。
                HSplitView {
                    SidebarView(
                        engine: engine,
                        aiEngine: aiEngine
                    )
                    .frame(minWidth: 300, idealWidth: 330, maxWidth: 380)
                    
                    HSplitView {
                        PDFCanvasView(
                            engine: engine,
                            currentPage: $currentPage
                        )
                        .frame(minWidth: 480, idealWidth: 720, maxWidth: .infinity)
                        
                        ResultInspectorView(
                            engine: engine,
                            aiEngine: aiEngine,
                            currentPage: $currentPage,
                            onStartExtraction: startExtractionAction
                        )
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
                    }
                    .frame(minWidth: 840, maxWidth: .infinity)
                }
                .transition(.opacity)
            }
        }
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        // 挂载 macOS 顶级 Window 工具栏支持，提供全键盘快捷键工作流
        .toolbar {
            // 全局页码联动翻页与回车跳转控制组。当前布局没有系统 Sidebar，避免放置无效折叠按钮。
            ToolbarItemGroup(placement: .principal) {
                if engine.pdfTotalPages > 0 {
                    HStack(spacing: 8) {
                        Button(action: {
                            if currentPage > 1 {
                                currentPage -= 1
                            }
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(currentPage <= 1 || engine.isProcessing)
                        .help("上一页")
                        
                        TextField("", text: $pageInput, onCommit: {
                            if let newPage = Int(pageInput.trimmingCharacters(in: .whitespacesAndNewlines)),
                               newPage >= 1 && newPage <= engine.pdfTotalPages {
                                currentPage = newPage
                            } else {
                                pageInput = String(currentPage) // 输入无效时复原
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
                            if currentPage < engine.pdfTotalPages {
                                currentPage += 1
                            }
                        }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(currentPage >= engine.pdfTotalPages || engine.isProcessing)
                        .help("下一页")
                    }
                }
            }
            
            // 核心文件导入/关闭控制
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
        }
        .onChange(of: currentPage) { oldValue, newValue in
            pageInput = String(newValue)
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
        currentPage = 1
        pageInput = "1"
    }
    
    /// 触发物理分段提取文字
    private func startExtractionAction() {
        let active = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
        let customWatermarks = UserDefaults.standard.string(forKey: "customWatermarks") ?? ""
        let ignoreCase = UserDefaults.standard.object(forKey: "ignoreCase") as? Bool ?? true
        let pageRangeString = UserDefaults.standard.string(forKey: "pageRangeString") ?? ""
        
        let scenarioRaw = UserDefaults.standard.string(forKey: "processingScenario") ?? PDFProcessingScenario.electronicTextWithTextWatermark.rawValue
        let scenario = PDFProcessingScenario(rawValue: scenarioRaw) ?? .electronicTextWithTextWatermark
        let eraseImageWatermark = UserDefaults.standard.object(forKey: "eraseImageWatermark") as? Bool ?? scenario.maskTextWatermarkBeforeOCR
        
        currentPage = 1
        
        engine.extractText(
            scenario: scenario,
            activeWatermarks: active,
            customWatermarks: customWatermarks,
            ignoreCase: ignoreCase,
            mode: scenario.extractionMode,
            watermarkRemovalMode: scenario.watermarkRemovalMode,
            enableWatermarkFilter: scenario.enableWatermarkFilter,
            eraseImageWatermark: eraseImageWatermark,
            pageRangeString: pageRangeString
        ) { _, _, _, _ in
            // 结果按页保存在 engine.extractedPagesText 中，右侧检查器直接读取该缓存。
        }
    }
    
    /// 触发物理分段 AI 净化
    private func startAIProcessingAction() {
        let showChanges = UserDefaults.standard.bool(forKey: "aiShowChanges")
        let passWatermarks = UserDefaults.standard.bool(forKey: "aiPassWatermarks")
        let active = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
        let customWatermarks = UserDefaults.standard.string(forKey: "customWatermarks") ?? ""
        let finalPrompt = AIPromptBuilder.composedPrompt(
            basePrompt: AIPromptBuilder.storedSystemPrompt(),
            showChanges: showChanges,
            passWatermarks: passWatermarks,
            activeWatermarks: active,
            customWatermarks: customWatermarks
        )
        
        aiEngine.processTextWithAI(
            extractedPages: engine.extractedPagesText,
            targetPages: Array(1...engine.pdfTotalPages),
            systemPrompt: finalPrompt
        )
    }
}
