import SwiftUI
import UniformTypeIdentifiers

// MARK: - 右侧统一结果检查器 (Liquid Glass Bento 场景卡片 + 胶囊词库 + 动态停止控制)

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
    
    // 手敲水印词输入缓存
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
            // 1. 顶部 Bento 场景选择与第一层级水印配置区 (Liquid Glass 现代舒展尺度)
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    scenarioBentoCards
                    watermarkChipsSection
                    pageRangeSection
                }
                .padding(Theme.Spacing.md)
            }
            .frame(maxHeight: 310)
            
            Divider()
            
            // 2. 结果检查器标签分栏与紧凑状态条 (大方工具栏)
            paneHeader
            
            Divider()
            
            // 3. 结果文本展示区 (Markdown 富文本排版双模预览)
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
            
            // 4. 底部主操作动作栏 (36px 现代 Liquid Glass 大按钮 + 动态停止)
            bottomActionBar
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
    }
    
    // MARK: - 1. Liquid Glass Bento 场景大卡片
    private var scenarioBentoCards: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("提取场景")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            
            VStack(spacing: Theme.Spacing.sm) {
                scenarioCard(
                    scenario: .electronicTextWithTextWatermark,
                    title: "电子文本",
                    subtitle: "直接读取可编辑文本层，速度最快",
                    icon: "doc.text"
                )
                
                scenarioCard(
                    scenario: .scannedTextWithTextWatermark,
                    title: "扫描正文",
                    subtitle: "图像 Vision OCR，支持色阶洗白水印",
                    icon: "photo.artframe"
                )
                
                scenarioCard(
                    scenario: .fullyScanned,
                    title: "全扫描件 / 公文",
                    subtitle: "适用于复杂排版，支持抹平红蓝印章",
                    icon: "doc.text.image" // 修复：使用官方可用标准图标
                )
            }
            
            // 上下文按需展开：扫描件专属滤镜开关 (大方副标题，杜绝失效的小问号)
            if processingScenario != .electronicTextWithTextWatermark {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("色阶去水印", isOn: $removeLightWatermarks)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12, weight: .medium))
                        Text("Core Image 智能拉伸明度，在 OCR 前洗白浅灰底纹水印。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 18)
                    }
                    
                    if processingScenario == .fullyScanned {
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("滤除印章", isOn: $removeColorStamps)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 12, weight: .medium))
                            Text("抹平红蓝彩色图层，消除审批章与公章对文字的粘连干扰。")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 18)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
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
            withAnimation(.easeInOut(duration: 0.18)) {
                processingScenario = scenario
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
            .frame(minHeight: Theme.Metric.cardMinHeight)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor).opacity(0.55)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .liquidGlassBorder(cornerRadius: Theme.Radius.md, isSelected: isSelected)
            .bentoCardShadow()
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 第一层级水印词库 (Liquid Glass Chips 标签胶囊)
    private var watermarkChipsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("水印过滤词")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if engine.isAnalyzingWatermarks {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }
            }
            
            // 候选词与自定义词胶囊流 (大方圆润手感)
            if !engine.watermarkCandidates.isEmpty || !customWatermarksList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        // 自动分析出的疑似水印词
                        ForEach(engine.watermarkCandidates.indices, id: \.self) { idx in
                            let candidate = engine.watermarkCandidates[idx]
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    engine.watermarkCandidates[idx].isSelected.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if candidate.isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    Text(candidate.text)
                                        .font(.system(size: 11, weight: candidate.isSelected ? .medium : .regular))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(candidate.isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                                .foregroundStyle(candidate.isSelected ? Color.white : Color.primary)
                                .clipShape(Capsule())
                                .liquidGlassPillBorder(isSelected: candidate.isSelected)
                            }
                            .buttonStyle(.plain)
                            .help("出现 \(candidate.occurrenceCount) 次，点击切换过滤状态")
                        }
                        
                        // 手动添加的自定义水印词
                        ForEach(customWatermarksList, id: \.self) { word in
                            HStack(spacing: 4) {
                                Text(word)
                                    .font(.system(size: 11, weight: .medium))
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        removeCustomWatermark(word)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.18))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                            .liquidGlassPillBorder(isSelected: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            
            // 手动输入新水印词栏 (30px 高度舒适输入)
            HStack(spacing: Theme.Spacing.xs) {
                TextField("输入词按回车添加...", text: $newWatermarkInput, onCommit: addCustomWatermark)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .frame(height: Theme.Metric.inputHeight)
                
                Button(action: addCustomWatermark) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(height: Theme.Metric.inputHeight)
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
                    .frame(width: 80)
            }
        }
        .font(.system(size: 11))
    }
    
    // MARK: - 2. 结果检查器标签分栏与大方工具栏
    private var paneHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Picker("", selection: $selectedPane) {
                ForEach(ResultPane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 140)
            
            Spacer()
            
            // 紧凑页码胶囊 [ Pg 1/45 ]
            if engine.pdfTotalPages > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 6, height: 6)
                    Text("Pg \(currentPage)/\(engine.pdfTotalPages)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .clipShape(Capsule())
                .liquidGlassPillBorder()
            }
            
            // 一键复制当前页
            Button(action: copyCurrentPageText) {
                Label(
                    engine.isCopied ? "已复制" : "复制",
                    systemImage: engine.isCopied ? "checkmark" : "doc.on.doc"
                )
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(currentActiveText.isEmpty)
            .help("复制当前页文本到系统剪贴板")
            
            // 修复：大方明确的导出下拉菜单 (删除多余空下拉箭头)
            Menu {
                Button("导出全部原文 (TXT)") { exportRawText() }
                Button("导出全部 AI 结果 (Markdown)") { exportAIText(asMarkdown: true) }
                Button("导出全部 AI 结果 (TXT)") { exportAIText(asMarkdown: false) }
            } label: {
                Label("导出...", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderedButton)
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
                        .scaleEffect(1.1)
                    Text("正在提取第 \(currentPage) 页...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if engine.extractedPagesText.isEmpty {
                EmptyResultState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "等待提取",
                    subtitle: "点击下方“提取文字”或按 ⌘R 开始识别当前 PDF。"
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
                        .scaleEffect(1.1)
                    Text(aiEngine.aiProgressStatus)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if aiEngine.aiPagesText.isEmpty,
                      aiEngine.aiProgressStatus.hasPrefix("错误") {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red)
                    Text("AI 净化遇到问题")
                        .font(.system(size: 14, weight: .semibold))
                    Text(aiEngine.aiProgressStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                    
                    Button("打开设置检查端点 (⌘,)") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
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
                        .controlSize(.small)
                        .frame(width: 150)
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 4)
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
    
    // MARK: - 4. 底部主操作动作栏 (36px 大气按钮 + 动态停止/取消)
    private var bottomActionBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            // 主操作按钮：提取文字 ⇄ 停止提取
            if engine.isProcessing {
                Button(action: { engine.cancelPDFExtraction() }) {
                    Label("停止提取", systemImage: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Metric.buttonHeightPrimary)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("立即中断当前提取任务")
            } else {
                Button(action: onStartExtraction) {
                    Label("提取文字", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Metric.buttonHeightPrimary)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    engine.pdfFileName.isEmpty
                        || engine.isAnalyzingWatermarks
                        || aiEngine.isAIProcessing
                )
                .keyboardShortcut("r", modifiers: .command)
                .help("开始执行文字提取 (⌘R)")
            }
            
            // 次操作按钮：AI 净化 ⇄ 停止净化
            if aiEngine.isAIProcessing {
                Button(action: { aiEngine.cancelAIProcessing() }) {
                    Label("停止净化", systemImage: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Metric.buttonHeightPrimary)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("立即中断 AI 本地流式网络请求")
            } else {
                Button(action: startAIPurificationAction) {
                    Label("AI 净化", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Metric.buttonHeightPrimary)
                }
                .buttonStyle(.bordered)
                .disabled(
                    engine.extractedPagesText.isEmpty
                        || engine.isProcessing
                )
                .help("让本地 AI 模型校对错字并输出 Markdown 排版")
            }
        }
        .padding(Theme.Spacing.md)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
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
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(tint.opacity(0.8))
            
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
