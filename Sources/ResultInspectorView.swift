import SwiftUI
import UniformTypeIdentifiers

// MARK: - 沉浸式文本工作室 (Text Studio - 遵循 Apple 生产力工作台规范)

@MainActor
private final class TextStudioViewState: ObservableObject {
    @Published var showOptionsDrawer = false
    @Published var newWatermarkInput = ""
}

struct ResultInspectorView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @ObservedObject var aiEngine: AIProcessingEngine
    @Binding var currentPage: Int
    var onStartExtraction: () -> Void

    // 视图范围：单页对照 vs 全篇大纲
    @AppStorage("studioViewScope") private var viewScope: StudioViewScope = .singlePage
    // 检查器分栏模式：提取原文 vs AI 净化
    @AppStorage("resultInspectorPane") private var selectedPane: ResultPane = .raw
    @AppStorage("aiPreviewMode") private var aiPreviewMode: AIPreviewMode = .formatted

    // 是否展开高级去水印与过滤设置抽屉与手敲词状态
    @StateObject private var studioState = TextStudioViewState()

    // 提取配置持久化项
    @AppStorage("processingScenario") private var processingScenario: PDFProcessingScenario = .electronicTextWithTextWatermark
    @AppStorage("removeLightWatermarks") private var removeLightWatermarks = true
    @AppStorage("removeColorStamps") private var removeColorStamps = false
    @AppStorage("eraseImageWatermark") private var eraseImageWatermark = false
    @AppStorage("pageRangeMode") private var pageRangeMode = 0 // 0: 全部页, 1: 当前页, 2: 自定义
    @AppStorage("pageRangeString") private var pageRangeString = ""
    @AppStorage("customWatermarks") private var customWatermarks = ""

    enum StudioViewScope: String, CaseIterable, Identifiable {
        case singlePage = "当前页对照"
        case fullDocument = "全篇大纲"

        var id: String { rawValue }
    }

    enum ResultPane: String, CaseIterable, Identifiable {
        case raw = "提取原文"
        case ai = "AI 净化"

        var id: String { rawValue }
    }

    enum AIPreviewMode: String, CaseIterable, Identifiable {
        case formatted = "排版渲染"
        case markdown = "源码"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部工作台主工具栏 (范围切换 + 模式切换 + 复制导出)
            studioHeader

            Divider()

            // 2. 高级过滤与参数折叠面板 (按需展开，绝不常驻挤压文本阅读高度)
            if studioState.showOptionsDrawer {
                optionsDrawer
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            // 3. 核心沉浸式文本展示区 (拥有全高度舒展空间)
            ZStack {
                switch selectedPane {
                case .raw:
                    rawTextStudioView
                case .ai:
                    aiTextStudioView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 4. 底部状态与主操作动作栏
            studioBottomBar
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    // MARK: - 1. 工作台主工具栏
    private var studioHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // 范围选择：当前页 vs 全篇大纲
            Picker("", selection: $viewScope) {
                ForEach(StudioViewScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 150)

            // 内容模式选择：原文 vs AI 净化
            Picker("", selection: $selectedPane) {
                ForEach(ResultPane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 140)

            Spacer()

            // 过滤设置展开按钮
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    studioState.showOptionsDrawer.toggle()
                }
            } label: {
                Image(systemName: studioState.showOptionsDrawer ? "slider.horizontal.3.fill" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(studioState.showOptionsDrawer ? "收起过滤与场景参数" : "展开去水印与场景设置")

            // 一键复制
            Button(action: copyActiveText) {
                Label(
                    engine.isCopied ? "已复制" : "复制",
                    systemImage: engine.isCopied ? "checkmark" : "doc.on.doc"
                )
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(currentActiveText.isEmpty)
            .help(viewScope == .singlePage ? "复制当前页文本到剪贴板" : "复制全篇文本到剪贴板")

            // 导出菜单
            Menu {
                Button("导出当前页原文 (TXT)") { exportSinglePageRawText() }
                Button("导出全篇原文 (TXT)") { exportRawText() }
                Divider()
                Button("导出全篇 AI 结果 (Markdown)") { exportAIText(asMarkdown: true) }
                Button("导出全篇 AI 结果 (TXT)") { exportAIText(asMarkdown: false) }
            } label: {
                Label("导出...", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .disabled(engine.extractedPagesText.isEmpty)
            .help("导出提取与净化的文本成果")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - 2. 折叠参数抽屉 (按需调出)
    private var optionsDrawer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // 场景提示与覆盖选择
            HStack {
                if !engine.detectedScenarioTitle.isEmpty {
                    Label(engine.detectedScenarioTitle, systemImage: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                Picker("场景模式:", selection: $processingScenario) {
                    ForEach(PDFProcessingScenario.allCases) { sc in
                        Text(sc.title).tag(sc)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 190)
            }

            // 滤镜开关
            if processingScenario != .electronicTextWithTextWatermark {
                HStack(spacing: Theme.Spacing.md) {
                    Toggle("色阶拉伸洗白浅灰水印", isOn: $removeLightWatermarks)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))

                    Toggle("红通道消除彩色公章", isOn: $removeColorStamps)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }
            }

            // 水印过滤词管理
            watermarkSection

            // 页码范围
            HStack(spacing: Theme.Spacing.sm) {
                Picker("提取范围:", selection: $pageRangeMode) {
                    Text("全部页 (\(engine.pdfTotalPages))").tag(0)
                    Text("当前页 (第 \(currentPage) 页)").tag(1)
                    Text("指定页码").tag(2)
                }
                .pickerStyle(.menu)
                .controlSize(.small)

                if pageRangeMode == 2 {
                    TextField("如 1-3, 5", text: $pageRangeString)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 90)
                }
            }
            .font(.system(size: 11))
        }
        .padding(Theme.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var watermarkSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("水印过滤词:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("添加自定义过滤词...", text: $studioState.newWatermarkInput, onCommit: addCustomWatermark)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 180)

                Button(action: addCustomWatermark) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(studioState.newWatermarkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // 候选词与自定义词标签
            if !engine.watermarkCandidates.isEmpty || !customWatermarksList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach($engine.watermarkCandidates) { $candidate in
                            Button {
                                candidate.isSelected.toggle()
                            } label: {
                                HStack(spacing: 3) {
                                    if candidate.isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    Text(candidate.text)
                                        .font(.system(size: 11))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(candidate.isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                .foregroundStyle(candidate.isSelected ? Color.white : Color.primary)
                                .clipShape(Capsule())
                                .subtleBorder(cornerRadius: 12, isSelected: candidate.isSelected)
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(customWatermarksList, id: \.self) { word in
                            HStack(spacing: 3) {
                                Text(word)
                                    .font(.system(size: 11))
                                Button {
                                    removeCustomWatermark(word)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 3. 核心文本展示区
    private var rawTextStudioView: some View {
        ZStack {
            if engine.isProcessing && engine.extractedPagesText.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("正在提取第 \(currentPage) 页...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if engine.extractedPagesText.isEmpty {
                EmptyResultState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "就绪，等待提取",
                    subtitle: "点击底部“提取文字”或按 ⌘R 开始识别。内置段落重构引擎将自动合并硬换行。"
                )
            } else {
                let displayedText = (viewScope == .singlePage)
                    ? (engine.extractedPagesText[currentPage] ?? "第 \(currentPage) 页暂未提取或文本为空。")
                    : engine.fullExtractedText

                ReadOnlyTextView(text: displayedText)
            }
        }
    }

    private var aiTextStudioView: some View {
        ZStack {
            if aiEngine.isAIProcessing && (aiEngine.aiPagesText[currentPage] ?? "").isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text(aiEngine.aiProgressStatus)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
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
                }
            } else if aiEngine.aiPagesText.isEmpty {
                EmptyResultState(
                    systemImage: "sparkles",
                    title: "等待 AI 净化",
                    subtitle: "提取完成后，点击下方“AI 净化”调用本地大模型校对错别字与段落排版。"
                )
            } else {
                let displayedAIText = (viewScope == .singlePage)
                    ? (aiEngine.aiPagesText[currentPage] ?? "第 \(currentPage) 页暂无 AI 净化内容。")
                    : joinedPages(aiEngine.aiPagesText)

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
                        .frame(width: 140)
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

                    if aiPreviewMode == .formatted {
                        ScrollView {
                            Text(LocalizedStringKey(displayedAIText))
                                .font(.system(.body, design: .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Theme.Spacing.md)
                        }
                    } else {
                        ReadOnlyTextView(text: displayedAIText)
                    }
                }
            }
        }
    }

    // MARK: - 4. 底部状态与操作栏
    private var studioBottomBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            // 左侧字数统计与状态
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 6, height: 6)
                    Text(statusTextDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !currentActiveText.isEmpty {
                    Text(viewScope == .singlePage ? "当前页: \(currentActiveText.count) 字" : "全篇累计: \(engine.totalExtractedWordCount) 字")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // 主提取按钮
            if engine.isProcessing {
                Button(action: { engine.cancelPDFExtraction() }) {
                    Label("停止提取", systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
            } else {
                Button(action: onStartExtraction) {
                    Label("提取文字", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(
                    engine.pdfFileName.isEmpty
                        || engine.isAnalyzingWatermarks
                        || aiEngine.isAIProcessing
                )
                .keyboardShortcut("r", modifiers: .command)
                .help("开始执行文字提取 (⌘R)")
            }

            // AI 净化按钮
            if aiEngine.isAIProcessing {
                Button(action: { aiEngine.cancelAIProcessing() }) {
                    Label("停止净化", systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.regular)
            } else {
                Button(action: startAIPurificationAction) {
                    Label("AI 净化", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(
                    engine.extractedPagesText.isEmpty
                        || engine.isProcessing
                )
                .help("让本地 AI 模型校对错字并润色")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - 辅助逻辑
    private var customWatermarksList: [String] {
        customWatermarks
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func addCustomWatermark() {
        let trimmed = studioState.newWatermarkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = customWatermarksList
        if !current.contains(trimmed) {
            current.append(trimmed)
            customWatermarks = current.joined(separator: ", ")
        }
        studioState.newWatermarkInput = ""
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

    private var statusTextDescription: String {
        if engine.isProcessing { return "正在提取文字..." }
        if aiEngine.isAIProcessing { return "AI 正在润色..." }
        if engine.extractedPagesText[currentPage] != nil { return "当前页已提取" }
        return "就绪"
    }

    private var currentActiveText: String {
        if selectedPane == .raw {
            return (viewScope == .singlePage)
                ? (engine.extractedPagesText[currentPage] ?? "")
                : engine.fullExtractedText
        } else {
            return (viewScope == .singlePage)
                ? (aiEngine.aiPagesText[currentPage] ?? "")
                : joinedPages(aiEngine.aiPagesText)
        }
    }

    private func copyActiveText() {
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

    private func exportSinglePageRawText() {
        guard let text = engine.extractedPagesText[currentPage] else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        let baseName = (engine.pdfFileName as NSString).deletingPathExtension
        savePanel.nameFieldStringValue = "\(baseName)_第\(currentPage)页.txt"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    engine.errorMessage = "导出失败：\(error.localizedDescription)"
                }
            }
        }
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

// MARK: - 空状态提示 (Apple Content Unavailable 风格)
private struct EmptyResultState: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)

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
