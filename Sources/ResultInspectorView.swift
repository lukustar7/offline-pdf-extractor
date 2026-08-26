import SwiftUI
import UniformTypeIdentifiers

// MARK: - 右侧统一结果检查器 (Bento 场景大卡片 + 第一层级胶囊词库 + 紧凑状态)

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
    
    // 新增手敲水印词临时缓存输入
    @AppStorage("newWatermarkInput") private var newWatermarkInput = ""
    
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
            // 1. 顶部 Bento 场景选择与第一层级水印配置区 (0 滚屏)
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    scenarioBentoCards
                    watermarkChipsSection
                    pageRangeSection
                }
                .padding(Theme.Spacing.md)
            }
            .frame(maxHeight: 280)
            
            Divider()
            
            // 2. 结果检查器标签分栏与紧凑状态条
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
    
    // MARK: - 1. Bento 场景大卡片选择器
    private var scenarioBentoCards: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("提取场景")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            VStack(spacing: Theme.Spacing.xs) {
                scenarioCard(
                    scenario: .electronicTextWithTextWatermark,
                    title: "电子文本",
                    subtitle: "直接读取可编辑文本层，速度最快",
                    icon: "doc.text"
                )
                
                scenarioCard(
                    scenario: .scannedTextWithTextWatermark,
                    title: "扫描正文",
                    subtitle: "图像 Vision OCR，支持色阶去水印",
                    icon: "photo.artframe"
                )
                
                scenarioCard(
                    scenario: .fullyScanned,
                    title: "全扫描件 / 公文",
                    subtitle: "适用于复杂排版，支持滤除红蓝印章",
                    icon: "stamp"
                )
            }
            
            // 上下文按需展开：扫描件专属滤镜开关
            if processingScenario != .electronicTextWithTextWatermark {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
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
                        .help("利用 Core Image 智能拉伸图像明度，在 OCR 前洗白浅色/半透明水印")
                        
                        if processingScenario == .fullyScanned {
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
                }
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
    }
    
    private func scenarioCard(
        scenario: PDFProcessingScenario,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        let isSelected = processingScenario == scenario
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                processingScenario = scenario
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.caption, design: .default).weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.3), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 第一层级水印词库 (Chips 标签胶囊)
    private var watermarkChipsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("水印过滤词")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if engine.isAnalyzingWatermarks {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.5)
                }
            }
            
            // 候选词与自定义词胶囊流
            if !engine.watermarkCandidates.isEmpty || !customWatermarksList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        // 自动分析出的疑似水印词
                        ForEach(engine.watermarkCandidates.indices, id: \.self) { idx in
                            let candidate = engine.watermarkCandidates[idx]
                            Button {
                                engine.watermarkCandidates[idx].isSelected.toggle()
                            } label: {
                                HStack(spacing: 3) {
                                    if candidate.isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    Text(candidate.text)
                                        .font(.system(size: 10))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(candidate.isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                .foregroundStyle(candidate.isSelected ? Color.white : Color.primary)
                                .clipShape(Capsule())
                                .subtleBorder(cornerRadius: Theme.Radius.pill)
                            }
                            .buttonStyle(.plain)
                            .help("出现 \(candidate.occurrenceCount) 次，点击切换过滤状态")
                        }
                        
                        // 手动添加的自定义水印词
                        ForEach(customWatermarksList, id: \.self) { word in
                            HStack(spacing: 2) {
                                Text(word)
                                    .font(.system(size: 10))
                                Button {
                                    removeCustomWatermark(word)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            
            // 手动输入新水印词栏 (回车即生成新胶囊)
            HStack(spacing: Theme.Spacing.xs) {
                TextField("输入词按回车添加...", text: $newWatermarkInput, onCommit: addCustomWatermark)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.caption2)
                
                Button(action: addCustomWatermark) {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newWatermarkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("添加自定义过滤词")
            }
        }
    }
    
    // MARK: - 页码范围选择
    private var pageRangeSection: some View {
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
    
    // MARK: - 2. 结果检查器标签分栏与紧凑状态条
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
            
            // 紧凑页码与状态胶囊 [ Pg 1/45 ]
            if engine.pdfTotalPages > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 5, height: 5)
                    Text("Pg \(currentPage)/\(engine.pdfTotalPages)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .clipShape(Capsule())
            }
            
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
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                    Text("AI 净化遇到问题")
                        .font(.system(.body).weight(.semibold))
                    Text(aiEngine.aiProgressStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                    
                    Button("打开设置检查端点 (⌘,)") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if aiEngine.aiPagesText.isEmpty {
                EmptyResultState(
                    systemImage: "sparkles",
                    title: "等待 AI 净化",
                    subtitle: "先完成原文提取，再点击下方“AI 净化”按页校对排版。"
                )
            } else {
                let pageText = aiEngine.aiPagesText[currentPage] ?? "当前页 AI 文本为空。"
                VStack(spacing: 0) {
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
    
    // MARK: - 辅助逻辑方法
    private var customWatermarksList: [String] {
        customWatermarks
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func addCustomWatermark() {
        let trimmed = newWatermarkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = customWatermarksList
        if !current.contains(trimmed) {
            current.append(trimmed)
            customWatermarks = current.joined(separator: ", ")
        }
        newWatermarkInput = ""
    }
    
    private func removeCustomWatermark(_ word: String) {
        var current = customWatermarksList
        current.removeAll { $0 == word }
        customWatermarks = current.joined(separator: ", ")
    }
    
    private var statusIndicatorColor: Color {
        if engine.isProcessing || aiEngine.isAIProcessing {
            return .orange
        }
        if engine.extractedPagesText[currentPage] != nil {
            return .green
        }
        return .secondary
    }
    
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
