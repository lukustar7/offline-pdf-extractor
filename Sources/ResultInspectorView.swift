import SwiftUI
import UniformTypeIdentifiers

// MARK: - 右侧结果检查器
struct ResultInspectorView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @ObservedObject var aiEngine: AIProcessingEngine
    @Binding var currentPage: Int
    var onStartExtraction: () -> Void
    
    @State private var selectedPane: ResultPane = .raw
    
    @AppStorage("systemPrompt") private var systemPrompt = AIPromptBuilder.defaultSystemPrompt
    @AppStorage("customWatermarks") private var customWatermarks = ""
    
    enum ResultPane: String, CaseIterable, Identifiable {
        case raw = "原文"
        case ai = "AI"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            
            Divider()
            
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
            
            inspectorActions
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
    }
    
    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: selectedPane == .raw ? "text.page" : "sparkles")
                    .font(.system(.headline).weight(.semibold))
                    .foregroundStyle(selectedPane == .raw ? Color.accentColor : .purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("结果")
                        .font(.system(.headline, design: .default).weight(.semibold))
                    Text("第 \(currentPage) 页")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if engine.isProcessing || aiEngine.isAIProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            
            Picker("", selection: $selectedPane) {
                ForEach(ResultPane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(Theme.Spacing.lg)
    }
    
    private var rawTextPane: some View {
        ZStack {
            if engine.isProcessing && engine.extractedPagesText.isEmpty {
                VStack(spacing: Theme.Spacing.lg) {
                    ProgressShimmerRing(progress: engine.progress, etaText: engine.etaString)
                    Text(engine.currentStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if engine.extractedPagesText.isEmpty {
                EmptyResultState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "等待提取",
                    subtitle: "点击下方“提取文字”开始识别当前 PDF。"
                )
            } else {
                let pageText = engine.extractedPagesText[currentPage] ?? "当前页文本为空或尚未处理。"
                ReadOnlyTextView(text: pageText)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }
    
    private var aiTextPane: some View {
        ZStack {
            if aiEngine.isAIProcessing && (aiEngine.aiPagesText[currentPage] ?? "").isEmpty {
                VStack(spacing: Theme.Spacing.lg) {
                    ProgressView()
                        .scaleEffect(1.15)
                    Text(aiEngine.aiProgressStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if aiEngine.aiPagesText.isEmpty {
                EmptyResultState(
                    systemImage: "sparkles",
                    title: "等待 AI 净化",
                    subtitle: "先提取文本，再让本地模型按页净化排版。"
                )
            } else {
                let pageText = aiEngine.aiPagesText[currentPage] ?? "当前页 AI 文本为空。"
                ReadOnlyTextView(text: pageText)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }
    
    private var inspectorActions: some View {
        VStack(spacing: Theme.Spacing.md) {
            if selectedPane == .raw {
                rawActions
            } else {
                aiActions
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
    }
    
    private var rawActions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if engine.isProcessing {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(engine.currentStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("停止") {
                        engine.cancelPDFExtraction()
                    }
                    .foregroundStyle(.red)
                }
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: onStartExtraction) {
                        Label("提取文字", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.pdfFileName.isEmpty)
                    
                    Button(action: exportRawText) {
                        Label("导出", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(engine.extractedPagesText.isEmpty)
                }
            }
        }
    }
    
    private var aiActions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if aiEngine.isAIProcessing {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(aiEngine.aiProgressStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("中止") {
                        aiEngine.cancelAIProcessing()
                    }
                    .foregroundStyle(.red)
                }
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: { startAIPurification(allPages: true) }) {
                        Label("全部页", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(engine.extractedPagesText.isEmpty)
                    
                    Button(action: { startAIPurification(allPages: false) }) {
                        Label("当前页", systemImage: "sparkles.rectangle.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(engine.extractedPagesText.isEmpty)
                }
                
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: { exportAIText(asMarkdown: false) }) {
                        Label("TXT", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(aiEngine.aiPagesText.isEmpty)
                    
                    Button(action: { exportAIText(asMarkdown: true) }) {
                        Label("Markdown", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(aiEngine.aiPagesText.isEmpty)
                }
            }
        }
    }
    
    private func startAIPurification(allPages: Bool) {
        let targetPages = allPages ? Array(1...engine.pdfTotalPages) : [currentPage]
        let showChanges = UserDefaults.standard.bool(forKey: "aiShowChanges")
        let passWatermarks = UserDefaults.standard.bool(forKey: "aiPassWatermarks")
        let activeWatermarks = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
        let finalPrompt = AIPromptBuilder.composedPrompt(
            basePrompt: systemPrompt,
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
        pages.keys.sorted().reduce(into: "") { result, page in
            if let text = pages[page] {
                result += "[第 \(page) 页]\n\(text)\n\n"
            }
        }
    }
    
    private func markdownPages(_ pages: [Int: String]) -> String {
        var content = "# \(engine.pdfFileName) AI 净化校对正文\n\n"
        for page in pages.keys.sorted() {
            if let text = pages[page] {
                content += "## 第 \(page) 页\n\n\(text)\n\n"
            }
        }
        return content
    }
}

private struct EmptyResultState: View {
    let systemImage: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.48))
            
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
