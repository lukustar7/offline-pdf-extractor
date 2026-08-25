import SwiftUI
import UniformTypeIdentifiers

// MARK: - 右侧统一结果检查器 (Apple HIG Inspector 架构)

/// 采用上部精简控制面板（0 滚屏）+ 下部富文本结果展示的双层现代架构。
struct ResultInspectorView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @ObservedObject var aiEngine: AIProcessingEngine
    @Binding var currentPage: Int
    var onStartExtraction: () -> Void
    
    // 检查器分栏模式
    @AppStorage("resultInspectorPane") private var selectedPane: ResultPane = .raw
    @AppStorage("aiPreviewMode") private var aiPreviewMode: AIPreviewMode = .formatted
    
    // 提取配置持久化项
    @AppStorage("processingScenario") private var processingScenario: PDFProcessingScenario = .electronicTextWithTextWatermark
    @AppStorage("removeLightWatermarks") private var removeLightWatermarks = true
    @AppStorage("removeColorStamps") private var removeColorStamps = false
    @AppStorage("eraseImageWatermark") private var eraseImageWatermark = false
    @AppStorage("pageRangeMode") private var pageRangeMode = 0 // 0: 全部页, 1: 当前页, 2: 自定义
    @AppStorage("pageRangeString") private var pageRangeString = ""
    @AppStorage("customWatermarks") private var customWatermarks = ""
    @AppStorage("showWatermarkSheet") private var showWatermarkSheet = false
    
    enum ResultPane: String, CaseIterable, Identifiable {
        case raw = "提取原文"
        case ai = "AI 净化"
        
        var id: String { rawValue }
    }
    
    enum AIPreviewMode: String, CaseIterable, Identifiable {
        case formatted = "排版预览"
        case markdown = "源码"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部精简控制卡片 (0 滚屏核心配置)
            inspectorConfigCard
            
            Divider()
            
            // 2. 结果检查器标签分栏
            paneHeader
            
            Divider()
            
            // 3. 结果文本展示区 (支持 Markdown 富文本预览与源码切换)
            ZStack {
                switch selectedPane {
                case .raw:
                    rawTextPane
                case .ai:
                    aiTextPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // 4. 底部主操作动作栏
            bottomActionBar
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
    }
    
    // MARK: - 1. 顶部精简控制卡片
    private var inspectorConfigCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // 场景切换
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("PDF 场景")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(processingScenario.title)
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
                
                Picker("", selection: $processingScenario) {
                    Text("电子文本").tag(PDFProcessingScenario.electronicTextWithTextWatermark)
                    Text("扫描正文").tag(PDFProcessingScenario.scannedTextWithTextWatermark)
                    Text("全扫描件").tag(PDFProcessingScenario.fullyScanned)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            
            // 扫描件高级去水印选项行 (精简图标 + Tooltip)
            if processingScenario != .electronicTextWithTextWatermark {
                HStack(spacing: Theme.Spacing.md) {
                    Toggle(isOn: $removeLightWatermarks) {
                        HStack(spacing: 2) {
                            Text("色阶去水印")
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .font(.caption2)
                    .help("利用 Core Image 智能拉伸图像明度，在 OCR 前洗白浅色杂印")
                    
                    Toggle(isOn: $removeColorStamps) {
                        HStack(spacing: 2) {
                            Text("滤除印章")
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .font(.caption2)
                    .help("抹平红蓝彩色图层，消除审批章与公章字符对正文 OCR 的粘连干扰")
                }
            }
            
            // 页码范围快捷选择
            HStack(spacing: Theme.Spacing.sm) {
                Picker("提取范围", selection: $pageRangeMode) {
                    Text("全部页 (\(engine.pdfTotalPages))").tag(0)
                    Text("当前页 (第 \(currentPage) 页)").tag(1)
                    Text("指定范围").tag(2)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                
                if pageRangeMode == 2 {
                    TextField("如 1-3, 5", text: $pageRangeString)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
            }
            .font(.caption2)
        }
        .padding(Theme.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
    
    // MARK: - 2. 结果检查器标签分栏
    private var paneHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Picker("", selection: $selectedPane) {
                ForEach(ResultPane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            
            Spacer()
            
            // 一键复制当前页
            Button(action: copyCurrentPageText) {
                Label(
                    engine.isCopied ? "已复制" : "复制",
                    systemImage: engine.isCopied ? "checkmark" : "doc.on.doc"
                )
                .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(currentActiveText.isEmpty)
            .help("复制当前页文本到系统剪贴板")
            
            // 导出下拉菜单
            Menu {
                Button("导出全部原文 (TXT)") { exportRawText() }
                Button("导出全部 AI 结果 (Markdown)") { exportAIText(asMarkdown: true) }
                Button("导出全部 AI 结果 (TXT)") { exportAIText(asMarkdown: false) }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption2)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .disabled(engine.extractedPagesText.isEmpty)
            .help("导出提取与净化文本")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }
    
    // MARK: - 3. 结果文本展示区
    private var rawTextPane: some View {
        ZStack {
            if engine.isProcessing && engine.extractedPagesText.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.0)
                    Text("正在提取第 \(currentPage) 页...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if engine.extractedPagesText.isEmpty {
                EmptyResultState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "等待提取",
                    subtitle: "点击下方“开始提取”或按 ⌘R 识别当前 PDF。"
                )
            } else {
                let pageText = engine.extractedPagesText[currentPage] ?? "当前页文本为空或未被提取。"
                ReadOnlyTextView(text: pageText)
            }
        }
    }
    
    private var aiTextPane: some View {
        ZStack {
            if aiEngine.isAIProcessing && (aiEngine.aiPagesText[currentPage] ?? "").isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.0)
                    Text(aiEngine.aiProgressStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if aiEngine.aiPagesText.isEmpty,
                      aiEngine.aiProgressStatus.hasPrefix("错误") {
                EmptyResultState(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "AI 净化遇到问题",
                    subtitle: aiEngine.aiProgressStatus,
                    tint: .red
                )
            } else if aiEngine.aiPagesText.isEmpty {
                EmptyResultState(
                    systemImage: "sparkles",
                    title: "等待 AI 净化",
                    subtitle: "先完成原文提取，再点击下方“AI 净化”按页校对排版。"
                )
            } else {
                let pageText = aiEngine.aiPagesText[currentPage] ?? "当前页 AI 文本为空。"
                VStack(spacing: 0) {
                    // AI 预览模式切换 (排版预览 vs Markdown 源码)
                    HStack {
                        Spacer()
                        Picker("", selection: $aiPreviewMode) {
                            ForEach(AIPreviewMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        .frame(width: 140)
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    
                    if aiPreviewMode == .formatted {
                        // 富文本 Markdown 渲染视图
                        ScrollView {
                            Text(LocalizedStringKey(pageText))
                                .font(.system(.body, design: .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Theme.Spacing.md)
                        }
                    } else {
                        ReadOnlyTextView(text: pageText)
                    }
                }
            }
        }
    }
    
    // MARK: - 4. 底部主操作动作栏
    private var bottomActionBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // 提取按钮
            Button(action: onStartExtraction) {
                Label("提取文字", systemImage: "play.fill")
                    .font(.system(.body).weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(
                engine.pdfFileName.isEmpty
                    || engine.isProcessing
                    || engine.isAnalyzingWatermarks
                    || aiEngine.isAIProcessing
            )
            .keyboardShortcut("r", modifiers: .command)
            .help("开始执行文字提取 (⌘R)")
            
            // AI 净化按钮
            Button(action: startAIPurificationAction) {
                Label("AI 净化", systemImage: "sparkles")
                    .font(.system(.body).weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(
                engine.extractedPagesText.isEmpty
                    || engine.isProcessing
                    || aiEngine.isAIProcessing
            )
            .help("让本地 AI 模型校对错字并输出 Markdown 排版")
        }
        .padding(Theme.Spacing.md)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }
    
    // MARK: - 逻辑方法
    private var currentActiveText: String {
        if selectedPane == .raw {
            return engine.extractedPagesText[currentPage] ?? ""
        } else {
            return aiEngine.aiPagesText[currentPage] ?? ""
        }
    }
    
    private func copyCurrentPageText() {
        let textToCopy = currentActiveText
        guard !textToCopy.isEmpty else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToCopy, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.15)) {
            engine.isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                engine.isCopied = false
            }
        }
    }
    
    private func startAIPurificationAction() {
        selectedPane = .ai
        let targetPages = engine.extractedPagesText.keys.sorted()
        let showChanges = UserDefaults.standard.bool(forKey: "aiShowChanges")
        let passWatermarks = UserDefaults.standard.bool(forKey: "aiPassWatermarks")
        let activeWatermarks = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
        let storedPrompt = AIPromptBuilder.storedSystemPrompt()
        let finalPrompt = AIPromptBuilder.composedPrompt(
            basePrompt: storedPrompt,
            showChanges: showChanges,
            passWatermarks: passWatermarks,
            activeWatermarks: activeWatermarks,
            customWatermarks: customWatermarks
        )
        
        aiEngine.processTextWithAI(
            extractedPages: engine.extractedPagesText,
            targetPages: targetPages,
            systemPrompt: finalPrompt
        )
    }
    
    private func exportRawText() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = (engine.pdfFileName as NSString).deletingPathExtension + ".txt"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try joinedPages(engine.extractedPagesText).write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    engine.errorMessage = "导出原文失败：\(error.localizedDescription)"
                }
            }
        }
    }
    
    private func exportAIText(asMarkdown: Bool) {
        let savePanel = NSSavePanel()
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        savePanel.allowedContentTypes = asMarkdown ? [markdownType] : [.plainText]
        let baseName = (engine.pdfFileName as NSString).deletingPathExtension
        savePanel.nameFieldStringValue = "\(baseName)_AI净化" + (asMarkdown ? ".md" : ".txt")
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let content = asMarkdown ? markdownPages(aiEngine.aiPagesText) : joinedPages(aiEngine.aiPagesText)
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    engine.errorMessage = "导出 AI 结果失败：\(error.localizedDescription)"
                }
            }
        }
    }
    
    private func joinedPages(_ pages: [Int: String]) -> String {
        pages.keys.sorted().compactMap { page in
            pages[page].map { "[第 \(page) 页]\n\($0)" }
        }
        .joined(separator: "\n\n")
    }
    
    private func markdownPages(_ pages: [Int: String]) -> String {
        let sections = pages.keys.sorted().compactMap { page in
            pages[page].map { "## 第 \(page) 页\n\n\($0)" }
        }
        return (["# \(engine.pdfFileName) AI 净化校对正文"] + sections)
            .joined(separator: "\n\n")
    }
}

// MARK: - 空状态提示
private struct EmptyResultState: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var tint: Color = .secondary
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(tint.opacity(0.8))
            
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.system(.body, design: .default).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if canImport(PreviewsMacros)
#Preview {
    ResultInspectorView(
        engine: PDFExtractorEngine(),
        aiEngine: AIProcessingEngine(),
        currentPage: .constant(1),
        onStartExtraction: {}
    )
    .frame(width: 360, height: 720)
}
#endif
