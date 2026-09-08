import SwiftUI
import UniformTypeIdentifiers

// MARK: - 主容器视图 (macOS 原生三栏工作台架构)

struct ContentView: View {
    @StateObject private var engine = PDFExtractorEngine()

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
                // 1. 文件尚未加载时，展示极简拖拽待机页
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
                // 2. 文件载入完成后，展示舒展的 缩略图侧栏 + PDF 原生画布 + 图文工作室
                HSplitView {
                    if showSidebar {
                        SidebarThumbnailView(engine: engine)
                            .frame(minWidth: 140, idealWidth: 170, maxWidth: 240)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    HSplitView {
                        PDFCanvasView(
                            engine: engine,
                            currentPage: $engine.currentPage
                        )
                        .frame(minWidth: 380, idealWidth: 540, maxWidth: .infinity)

                        if showInspector {
                            ResultInspectorView(
                                engine: engine,
                                currentPage: $engine.currentPage,
                                onStartExtraction: startExtractionAction
                            )
                            .frame(minWidth: 380, idealWidth: 480, maxWidth: 850)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(minWidth: 400, maxWidth: .infinity)
                }
                .transition(.opacity)
            }
        }
        .background(.windowBackground)
        .sheet(isPresented: $engine.showWelcomeSheet) {
            WelcomeView()
        }
        .onAppear {
            if !hasShownWelcomeSheet {
                engine.showWelcomeSheet = true
            }
        }
        // 挂载 macOS 顶级 Window 工具栏支持
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

            // 2. 中间：页码控制组与智能格式探针徽章
            ToolbarItemGroup(placement: .principal) {
                if engine.pdfTotalPages > 0 {
                    HStack(spacing: Theme.Spacing.md) {
                        HStack(spacing: Theme.Spacing.xs) {
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
                            .frame(width: 48)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .disabled(engine.isProcessing)
                            .help("输入页码回车跳转")

                            Text("/ \(engine.pdfTotalPages) 页")
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

                        // 智能探针格式胶囊
                        if !engine.detectedScenarioTitle.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: engine.hasTextLayer ? "bolt.fill" : "wand.and.stars")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentColor)
                                Text(engine.detectedScenarioTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                            .clipShape(Capsule())
                            .subtleBorder(cornerRadius: 12)
                        }
                    }
                }
            }

            // 3. 右侧：操作按钮与工作室折叠
            ToolbarItemGroup(placement: .primaryAction) {
                if engine.pdfFileName.isEmpty {
                    Button(action: openFileAction) {
                        Label("导入 PDF", systemImage: "doc.badge.plus")
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("导入 PDF 文件并自动分析 (⌘O)")
                } else {
                    // 扫描件场景下的去水印对比开关
                    if !engine.hasTextLayer {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                engine.isComparisonMode.toggle()
                                if engine.isComparisonMode {
                                    let light = UserDefaults.standard.object(forKey: "removeLightWatermarks") as? Bool ?? true
                                    let stamps = UserDefaults.standard.object(forKey: "removeColorStamps") as? Bool ?? false
                                    engine.updateComparisonPreview(removeLightWatermarks: light, removeColorStamps: stamps)
                                }
                            }
                        } label: {
                            Label(
                                engine.isComparisonMode ? "退出对比" : "去水印效果对比",
                                systemImage: engine.isComparisonMode ? "eye.slash" : "eye"
                            )
                        }
                        .help("查看 Core Image 通道过滤前后的去水印净化对比效果")
                    }

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
                    .help(showInspector ? "收起图文工作室 (⌘⌥I)" : "展开图文工作室 (⌘⌥I)")
                    .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
        }
        .onChange(of: engine.currentPage) { oldValue, newValue in
            engine.pageInput = String(newValue)
            engine.preloadThumbnailsAround(pageNumber: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenFileNotification"))) { _ in
            openFileAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartExtractionNotification"))) { _ in
            if !engine.pdfFileName.isEmpty && !engine.isProcessing && !engine.isAnalyzingWatermarks {
                startExtractionAction()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExportDocxNotification"))) { _ in
            if !engine.extractedPages.isEmpty {
                exportDocxShortcut()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowWelcomeSheetNotification"))) { _ in
            engine.showWelcomeSheet = true
        }
        .onDisappear {
            engine.cancelPDFExtraction(showStatus: false)
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
        engine.loadPDF(url: url)
    }

    /// 触发物理分段提取文字与插图
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

    /// 快捷键触发导出 Word 文档
    private func exportDocxShortcut() {
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
}

#if canImport(PreviewsMacros)
#Preview {
    ContentView()
        .frame(minWidth: 1_000, minHeight: 700)
}
#endif
