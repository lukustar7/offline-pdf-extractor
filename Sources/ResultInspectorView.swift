import SwiftUI
import UniformTypeIdentifiers

// MARK: - 沉浸式图文工作室 (Document Studio - Apple 原生生产力设计规范)

@MainActor
private final class DocumentStudioState: ObservableObject {
    @Published var showOptionsDrawer = false
    @Published var newWatermarkInput = ""
}

struct ResultInspectorView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @Binding var currentPage: Int
    var onStartExtraction: () -> Void

    // 视图范围：当前页对照 vs 全篇大纲
    @AppStorage("studioViewScope") private var viewScope: StudioViewScope = .singlePage

    // 内部状态对象
    @StateObject private var studioState = DocumentStudioState()

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

    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部工作台工具栏 (大气标准尺寸)
            studioHeader

            Divider()

            // 2. 高级过滤与提取参数折叠抽屉
            if studioState.showOptionsDrawer {
                optionsDrawer
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            // 3. 核心三大处理模式横排大卡片按钮
            modeSelectorRow
            Divider()

            // 4. 核心图文混排内容展示区
            documentContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 4. 底部状态与大尺寸操作栏
            studioBottomBar
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    // MARK: - 1. 工作台主工具栏 (大气从容)
    private var studioHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            // 范围切换：当前页 vs 全篇大纲 (标准 regular 尺寸)
            Picker("", selection: $viewScope) {
                ForEach(StudioViewScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .frame(width: 190)

            Spacer()

            // 参数设置展开按钮
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    studioState.showOptionsDrawer.toggle()
                }
            } label: {
                Label(
                    studioState.showOptionsDrawer ? "收起参数" : "去印与过滤",
                    systemImage: studioState.showOptionsDrawer ? "slider.horizontal.3.fill" : "slider.horizontal.3"
                )
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(studioState.showOptionsDrawer ? "收起去印参数与页码设置" : "展开去印参数与页码设置")

            // 核心主导出按钮：直接导出包含所有内嵌图片的 Word 文档 (.docx)
            Button(action: exportDocxAction) {
                Label("导出 Word (.docx)", systemImage: "arrow.down.doc.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(engine.extractedPages.isEmpty)
            .help("将提取的文字与完整截取插图一并导出为 Word 文档 (.docx)")

            // 更多操作下拉菜单
            Menu {
                Button("拷贝全部纯文本") {
                    copyActiveText()
                }
                Divider()
                Button("导出 Markdown 压缩包 (.zip 含插图)") {
                    exportMarkdownZipAction()
                }
                Button("拷贝 Markdown 格式文本") {
                    copyMarkdownText()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderedButton)
            .controlSize(.regular)
            .disabled(engine.extractedPages.isEmpty)
            .help("更多导出与复制操作")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    // MARK: - 2. 折叠参数抽屉
    private var optionsDrawer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // 扫描件滤镜开关
            if processingScenario != .electronicTextWithTextWatermark {
                HStack(spacing: Theme.Spacing.lg) {
                    Toggle("色阶拉伸洗白浅灰水印", isOn: $removeLightWatermarks)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))

                    Toggle("红通道消除彩色公章", isOn: $removeColorStamps)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
            }

            // 水印过滤词管理
            watermarkSection

            // 提取范围
            HStack(spacing: Theme.Spacing.md) {
                Picker("提取范围:", selection: $pageRangeMode) {
                    Text("全部页面 (共 \(engine.pdfTotalPages) 页)").tag(0)
                    Text("仅当前页 (第 \(currentPage) 页)").tag(1)
                    Text("指定页码范围").tag(2)
                }
                .pickerStyle(.menu)
                .controlSize(.regular)

                if pageRangeMode == 2 {
                    TextField("如 1-3, 5", text: $pageRangeString)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                        .frame(width: 100)
                }
            }
            .font(.system(size: 12))
        }
        .padding(Theme.Spacing.lg)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var watermarkSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("水印过滤词:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("输入要滤除的水印词...", text: $studioState.newWatermarkInput, onCommit: addCustomWatermark)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                    .frame(maxWidth: 200)

                Button(action: addCustomWatermark) {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(studioState.newWatermarkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // 候选词与自定义词标签流
            if !engine.watermarkCandidates.isEmpty || !customWatermarksList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach($engine.watermarkCandidates) { $candidate in
                            Button {
                                candidate.isSelected.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    if candidate.isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    Text(candidate.text)
                                        .font(.system(size: 12))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(candidate.isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                .foregroundStyle(candidate.isSelected ? Color.white : Color.primary)
                                .clipShape(Capsule())
                                .subtleBorder(cornerRadius: 14, isSelected: candidate.isSelected)
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(customWatermarksList, id: \.self) { word in
                            HStack(spacing: 4) {
                                Text(word)
                                    .font(.system(size: 12))
                                Button {
                                    removeCustomWatermark(word)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: - 3. 三大处理模式横排大卡片按钮
    private var modeSelectorRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(PDFProcessingScenario.allCases) { scenario in
                ModeCardButton(
                    scenario: scenario,
                    isSelected: processingScenario == scenario
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        processingScenario = scenario
                        if scenario == .fullyScanned {
                            removeLightWatermarks = true
                            removeColorStamps = true
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.2))
    }

    // MARK: - 4. 核心图文混排展示区 (开阔阅读流)
    private var documentContentArea: some View {
        ZStack {
            if engine.isProcessing && engine.extractedPages.isEmpty {
                VStack(spacing: Theme.Spacing.lg) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在提取图文内容...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if engine.extractedPages.isEmpty {
                EmptyStateView(
                    systemImage: "doc.richtext",
                    title: "等待提取图文",
                    subtitle: "点击底部“开始提取”或按 ⌘R。系统将自动重构自然段落，并精准截取文档中的照片、图表与公式，按顺序穿插呈现。"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        if viewScope == .singlePage {
                            // 单页对照视图
                            if let pageContent = engine.extractedPages[currentPage] {
                                PageContentView(page: pageContent)
                            } else {
                                Text("第 \(currentPage) 页尚未提取。点击下方“开始提取”即可识别。")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .padding(Theme.Spacing.xl)
                            }
                        } else {
                            // 全篇大纲视图
                            let sortedPages = engine.extractedPages.keys.sorted().compactMap { engine.extractedPages[$0] }
                            ForEach(sortedPages, id: \.pageNumber) { pageContent in
                                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                    HStack {
                                        Text("第 \(pageContent.pageNumber) 页")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Rectangle()
                                            .fill(Color(nsColor: .separatorColor).opacity(0.4))
                                            .frame(height: 1)
                                    }
                                    .padding(.top, Theme.Spacing.sm)

                                    PageContentView(page: pageContent)
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
        }
    }

    // MARK: - 4. 底部状态与操作栏 (大气标准尺寸 36px)
    private var studioBottomBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // 左侧状态统计
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 7, height: 7)
                    Text(statusTextDescription)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if !engine.extractedPages.isEmpty {
                    Text("已提取 \(engine.extractedPages.count) 页 · 共 \(engine.totalExtractedWordCount) 字 · \(engine.totalExtractedImagesCount) 张插图")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // 快捷拷贝文字
            Button(action: copyActiveText) {
                Label(
                    engine.isCopied ? "已拷贝文本" : "拷贝文本",
                    systemImage: engine.isCopied ? "checkmark" : "doc.on.doc"
                )
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, Theme.Spacing.xs)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(engine.extractedPages.isEmpty)
            .help("拷贝已提取的所有段落纯文本")

            // 主提取动作按钮 (高度 36px 大气胶囊)
            if engine.isProcessing {
                Button(action: { engine.cancelPDFExtraction() }) {
                    Label("停止提取", systemImage: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button(action: onStartExtraction) {
                    Label("开始提取全文与插图", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(engine.pdfFileName.isEmpty || engine.isAnalyzingWatermarks)
                .keyboardShortcut("r", modifiers: .command)
                .help("开始执行全文与插图提取 (⌘R)")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    // MARK: - 辅助与导出逻辑
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
        if engine.isProcessing { return .orange }
        if !engine.extractedPages.isEmpty { return .green }
        return .secondary
    }

    private var statusTextDescription: String {
        if engine.isProcessing { return "正在提取图文..." }
        if !engine.extractedPages.isEmpty { return "提取完毕" }
        return "就绪"
    }

    private func copyActiveText() {
        let textToCopy: String
        if viewScope == .singlePage {
            textToCopy = engine.extractedPages[currentPage]?.fullText ?? ""
        } else {
            textToCopy = engine.fullExtractedText
        }
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

    private func copyMarkdownText() {
        let (md, _) = engine.buildMarkdown()
        guard !md.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(md, forType: .string)
    }

    /// 导出为 Word 文档 (.docx)
    private func exportDocxAction() {
        guard !engine.extractedPages.isEmpty else { return }
        let savePanel = NSSavePanel()
        let docxType = UTType(filenameExtension: "docx") ?? .data
        savePanel.allowedContentTypes = [docxType]
        let baseName = (engine.pdfFileName as NSString).deletingPathExtension
        savePanel.nameFieldStringValue = "\(baseName).docx"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let docxData = try engine.buildDocxData()
                    try docxData.write(to: url)
                } catch {
                    engine.errorMessage = "导出 Word 文档失败：\(error.localizedDescription)"
                }
            }
        }
    }

    /// 导出为 Markdown 压缩包 (.zip)
    private func exportMarkdownZipAction() {
        guard !engine.extractedPages.isEmpty else { return }
        let savePanel = NSSavePanel()
        let zipType = UTType(filenameExtension: "zip") ?? .data
        savePanel.allowedContentTypes = [zipType]
        let baseName = (engine.pdfFileName as NSString).deletingPathExtension
        savePanel.nameFieldStringValue = "\(baseName)_Markdown.zip"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let (markdown, images) = engine.buildMarkdown()
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: tempDir) }

                    // 写出 markdown 文件
                    let mdURL = tempDir.appendingPathComponent("\(baseName).md")
                    try markdown.write(to: mdURL, atomically: true, encoding: .utf8)

                    // 写出 images 文件夹
                    if !images.isEmpty {
                        let imgDir = tempDir.appendingPathComponent("images")
                        try FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
                        for item in images {
                            let fileURL = imgDir.appendingPathComponent(item.filename)
                            if let tiffData = item.image.tiffRepresentation,
                               let bitmap = NSBitmapImageRep(data: tiffData),
                               let pngData = bitmap.representation(using: .png, properties: [:]) {
                                try pngData.write(to: fileURL)
                            }
                        }
                    }

                    // 清理可能已存在的同名目标文件，防止 zip 变为追加模式损坏压缩包
                    try? FileManager.default.removeItem(at: url)

                    // 调用 zip 打包
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    process.currentDirectoryURL = tempDir
                    process.arguments = ["-q", "-r", url.path, "."]
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        throw NSError(
                            domain: "ZipExportError",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "压缩包生成失败，退出码：\(process.terminationStatus)"]
                        )
                    }
                } catch {
                    engine.errorMessage = "导出 Markdown 失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 单页图文混排展示子视图
private struct PageContentView: View {
    let page: ExtractedPageContent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(page.elements) { element in
                switch element {
                case .paragraph(let text):
                    Text(text)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .image(let extImg):
                    IllustrationCardView(image: extImg)
                }
            }
        }
    }
}

// MARK: - 单张插图卡片
private struct IllustrationCardView: View {
    let image: ExtractedImage

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(nsImage: image.nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 480)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .subtleBorder(cornerRadius: Theme.Radius.md)
                .bentoCardShadow()
                .contextMenu {
                    Button("拷贝此图片") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.writeObjects([image.nsImage])
                    }
                    Button("另存为图片...") {
                        saveSingleImage()
                    }
                }

            HStack {
                Text("插图 P\(image.pageNumber)-\(image.imageIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([image.nsImage])
                } label: {
                    Label("拷贝图片", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func saveSingleImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "P\(image.pageNumber)_\(image.imageIndex).png"
        savePanel.begin { res in
            if res == .OK, let targetURL = savePanel.url {
                if let tiff = image.nsImage.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: targetURL)
                }
            }
        }
    }
}

// MARK: - 空状态提示
private struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, Theme.Spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 单个处理模式大卡片按钮
private struct ModeCardButton: View {
    let scenario: PDFProcessingScenario
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: scenario.systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Text(scenario.title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Text(scenario.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.secondary : Color.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
        .help(scenario.statusDescription)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            .strokeBorder(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                lineWidth: isSelected ? 1.5 : 0.8
            )
    }
}

