import SwiftUI

// MARK: - 主容器视图
struct ContentView: View {
    @StateObject private var engine = PDFExtractorEngine()
    @StateObject private var aiEngine = AIProcessingEngine()
    
    @State private var resultText = ""
    @State private var txtFileURL: URL? = nil
    @State private var mdFileURL: URL? = nil
    
    // selectedTab: 0 -> PDF 预览, 1 -> 原始提取文本, 2 -> 本地 AI 纠错净化
    @State private var selectedTab = 0
    
    var body: some View {
        HSplitView {
            // 左侧控制区
            SidebarView(
                engine: engine,
                aiEngine: aiEngine,
                resultText: $resultText,
                txtFileURL: $txtFileURL,
                mdFileURL: $mdFileURL,
                selectedTab: $selectedTab
            )
            .frame(minWidth: 280, maxWidth: 500)
            
            // 右侧主展示区
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
        .background(
            LinearGradient(
                colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        // 挂载全局键盘快捷键组件 (利用隐藏按钮机制，不污染 UI 且符合原生 SwiftUI 设计)
        .background(
            Group {
                Button(action: openFileAction) { Text("") }
                    .keyboardShortcut("o", modifiers: .command)
                
                Button(action: startExtractionKeyboardAction) { Text("") }
                    .keyboardShortcut("r", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        )
    }
    
    /// 键盘快捷键 ⌘O 打开 PDF 逻辑
    private func openFileAction() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            _ = engine.loadPDF(url: url)
        }
    }
    
    /// 键盘快捷键 ⌘R 开始提取逻辑 (包含防并发机制与参数升级)
    private func startExtractionKeyboardAction() {
        guard !engine.pdfFileName.isEmpty && !engine.isProcessing && !aiEngine.isAIProcessing else { return }
        
        // 读取由 AppStorage 自动存在 UserDefaults 里的全局设置
        let modeRaw = UserDefaults.standard.string(forKey: "extractionMode") ?? ExtractionMode.smart.rawValue
        let mode = ExtractionMode(rawValue: modeRaw) ?? .smart
        let watermarkRemovalModeRaw = UserDefaults.standard.string(forKey: "watermarkRemovalMode") ?? WatermarkRemovalMode.auto.rawValue
        let watermarkRemovalMode = WatermarkRemovalMode(rawValue: watermarkRemovalModeRaw) ?? .auto
        let enableWatermarkFilter = UserDefaults.standard.object(forKey: "enableWatermarkFilter") as? Bool ?? true
        
        let ignoreCase = UserDefaults.standard.object(forKey: "ignoreCase") as? Bool ?? true
        let eraseImageWatermark = UserDefaults.standard.object(forKey: "eraseImageWatermark") as? Bool ?? false
        let pageRangeString = UserDefaults.standard.string(forKey: "pageRangeString") ?? ""
        let customWatermarks = UserDefaults.standard.string(forKey: "customWatermarks") ?? ""
        
        let active = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
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
                self.selectedTab = 0 // 跳转至提取文本 Tab (0-indexed)
            }
        }
    }
}
