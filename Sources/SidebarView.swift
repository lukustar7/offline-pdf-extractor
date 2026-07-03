import SwiftUI

// MARK: - 左侧控制侧边栏视图 (macOS 原生 Inspector 风格)
struct SidebarView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @ObservedObject var aiEngine: AIProcessingEngine
    
    // 使用 @AppStorage 对用户偏好进行持久化保存，防止重启丢失配置
    @AppStorage("extractionMode") private var extractionMode: ExtractionMode = .smart
    @AppStorage("watermarkRemovalMode") private var watermarkRemovalMode: WatermarkRemovalMode = .auto
    @AppStorage("enableWatermarkFilter") private var enableWatermarkFilter = true
    @AppStorage("ignoreCase") private var ignoreCase = true
    @AppStorage("eraseImageWatermark") private var eraseImageWatermark = false
    @AppStorage("pageRangeString") private var pageRangeString = ""
    @AppStorage("customWatermarks") private var customWatermarks = ""
    
    // 用户真正理解的三类 PDF 场景，驱动底层提取与去水印管线。
    @AppStorage("processingScenario") private var processingScenario: PDFProcessingScenario = .electronicTextWithTextWatermark
    
    @AppStorage("aiShowChanges") private var aiShowChanges = false
    @AppStorage("aiPassWatermarks") private var aiPassWatermarks = false
    
    @AppStorage("systemPrompt") private var systemPrompt = AIPromptBuilder.defaultSystemPrompt
    
    // 侧边栏当前激活的 Tab：0 -> 提取设置, 1 -> AI 设置
    @State private var activeSidebarTab = 0
    @State private var isSettingsExpanded = true
    @State private var isWatermarkExpanded = true
    @State private var isAIExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            // macOS 侧边栏属性卡片顶部标题，使用标准 Source List Group Header 风格
            HStack {
                Text("处理设置")
                    .font(.system(.caption, design: .default).weight(.bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)
            
            // Segmented Picker 分栏
            Picker("", selection: $activeSidebarTab) {
                Text("提取设置").tag(0)
                Text(aiEngine.isAIProcessing ? "AI 设置 ●" : "AI 设置").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.md)
            
            Divider()
                .padding(.horizontal, Theme.Spacing.md)
            
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    
                    // 异常日志气泡展示
                    if let error = engine.errorMessage {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundColor(.red)
                                .font(.system(.body))
                            
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("需要处理的问题")
                                    .font(.system(.caption, design: .default).weight(.bold))
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.system(.caption2))
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation {
                                    engine.errorMessage = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清除错误信息")
                        }
                        .padding(Theme.Spacing.md)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.15), lineWidth: 1)
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, Theme.Spacing.sm)
                    }
                    
                    if activeSidebarTab == 0 {
                        // ==================== 提取设置面板 ====================
                        
                        // 已载入文件时的 FileInfo 视图
                        if !engine.pdfFileName.isEmpty {
                            FileInfoView(
                                name: engine.pdfFileName,
                                size: engine.pdfFileSize,
                                pages: engine.pdfTotalPages,
                                onClear: {
                                    engine.clear()
                                    aiEngine.clear()
                                }
                            )
                            .padding(.top, Theme.Spacing.sm)
                            
                            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                                // 提取配置折叠组
                                DisclosureGroup(isExpanded: $isSettingsExpanded) {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                        
                                        // 1. 三类真实 PDF 场景选择器
                                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                            Text("PDF 场景")
                                                .font(.system(.caption, design: .default).weight(.semibold))
                                                .foregroundColor(.secondary)
                                            
                                            VStack(spacing: Theme.Spacing.sm) {
                                                SettingSelectorCard(
                                                    title: PDFProcessingScenario.electronicTextWithTextWatermark.title,
                                                    subTitle: PDFProcessingScenario.electronicTextWithTextWatermark.subtitle,
                                                    isSelected: processingScenario == .electronicTextWithTextWatermark,
                                                    systemImage: "doc.text",
                                                    themeColor: .blue,
                                                    action: { processingScenario = .electronicTextWithTextWatermark }
                                                )
                                                
                                                SettingSelectorCard(
                                                    title: PDFProcessingScenario.scannedTextWithTextWatermark.title,
                                                    subTitle: PDFProcessingScenario.scannedTextWithTextWatermark.subtitle,
                                                    isSelected: processingScenario == .scannedTextWithTextWatermark,
                                                    systemImage: "doc.viewfinder",
                                                    themeColor: .indigo,
                                                    action: { processingScenario = .scannedTextWithTextWatermark }
                                                )
                                                
                                                SettingSelectorCard(
                                                    title: PDFProcessingScenario.fullyScanned.title,
                                                    subTitle: PDFProcessingScenario.fullyScanned.subtitle,
                                                    isSelected: processingScenario == .fullyScanned,
                                                    systemImage: "scanner",
                                                    themeColor: .orange,
                                                    action: { processingScenario = .fullyScanned }
                                                )
                                            }
                                            
                                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                                Image(systemName: scenarioSymbolName)
                                                    .font(.system(.callout).weight(.semibold))
                                                    .foregroundColor(scenarioTintColor)
                                                    .frame(width: 18)
                                                Text(processingScenario.statusDescription)
                                                    .font(.system(.caption2))
                                                    .foregroundColor(.secondary)
                                                    .lineSpacing(2)
                                            }
                                            .padding(Theme.Spacing.sm)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(scenarioTintColor.opacity(0.08))
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(scenarioTintColor.opacity(0.16), lineWidth: 1)
                                            )
                                            .padding(.top, Theme.Spacing.xs)
                                        }
                                        .padding(.vertical, Theme.Spacing.xs)
                                        
                                        // 2. 页码范围输入框
                                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                            Text("指定提取页码范围 (如 1-5, 8, 10-12)")
                                                .font(.system(.caption2, design: .default).weight(.medium))
                                                .foregroundColor(.secondary)
                                            
                                            TextField("留空则提取全部页面", text: $pageRangeString)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.subheadline)
                                                .accessibilityLabel("页码提取范围输入框")
                                        }
                                        
                                        Toggle("忽略字母大小写", isOn: $ignoreCase)
                                            .toggleStyle(.checkbox)
                                        
                                        if processingScenario == .scannedTextWithTextWatermark {
                                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                                Toggle("高级：OCR 前遮盖电子水印区域", isOn: $eraseImageWatermark)
                                                    .toggleStyle(.checkbox)
                                                
                                                Text("默认关闭。只有当电子水印本身严重干扰 OCR 时再尝试；如果水印压住正文，遮盖会同时抹掉下方正文。")
                                                    .font(.system(.caption2))
                                                    .foregroundColor(.secondary)
                                                    .lineSpacing(2)
                                            }
                                        }
                                    }
                                    .padding(.leading, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.sm)
                                } label: {
                                    Label("提取配置", systemImage: "slider.horizontal.3")
                                        .font(.system(.body, design: .default).weight(.bold))
                                        .foregroundColor(.primary)
                                }
                                
                                Divider()
                                    .padding(.horizontal, Theme.Spacing.xs)
                                
                                DisclosureGroup(isExpanded: $isWatermarkExpanded) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        if engine.watermarkCandidates.isEmpty {
                                            Text("未检测到高频电子水印词。全扫描件可在下方手动添加 OCR 后需要过滤的水印残留。")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .padding(.vertical, Theme.Spacing.xs)
                                        } else {
                                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                                Text("高频疑似水印词")
                                                    .font(.system(.caption, design: .default).weight(.semibold))
                                                    .foregroundColor(.secondary)
                                                Text("这些词在多页重复出现。若其中有正文内容，请取消勾选，避免误删。")
                                                    .font(.system(.caption2))
                                                    .foregroundColor(.secondary)
                                                    .lineSpacing(2)
                                            }
                                            .padding(.bottom, Theme.Spacing.xs)
                                            
                                            ForEach($engine.watermarkCandidates) { $candidate in
                                                Toggle(isOn: $candidate.isSelected) {
                                                    HStack {
                                                        Text(candidate.text)
                                                            .font(.system(.body).weight(.medium))
                                                            .lineLimit(1)
                                                        Spacer()
                                                        Text("\(candidate.occurrenceCount) 页")
                                                            .font(.system(.caption2))
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                .toggleStyle(.checkbox)
                                            }
                                        }
                                        
                                        Divider()
                                            .padding(.vertical, Theme.Spacing.xs)
                                        
                                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                            Text("手动添加过滤词 (逗号或换行隔开)")
                                                .font(.system(.caption2, design: .default).weight(.medium))
                                                .foregroundColor(.secondary)
                                            
                                            TextEditor(text: $customWatermarks)
                                                .font(.system(.body, design: .default))
                                                .frame(height: 50)
                                                .padding(Theme.Spacing.xs)
                                                .background(Color(nsColor: .textBackgroundColor))
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                                )
                                                .accessibilityLabel("手动添加过滤词编辑框")
                                        }
                                    }
                                    .padding(.leading, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.sm)
                                } label: {
                                    Label("水印词管理", systemImage: "tag")
                                        .font(.system(.body, design: .default).weight(.bold))
                                        .foregroundColor(.primary)
                                }
                                .transition(.opacity)
                            }
                        }
                    } else {
                        // ==================== AI 设置面板 ====================
                        DisclosureGroup(isExpanded: $isAIExpanded) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text("API 服务地址")
                                        .font(.system(.caption2, design: .default).weight(.medium))
                                        .foregroundColor(.secondary)
                                    
                                    TextField("http://localhost:11434/v1", text: $aiEngine.aiApiBaseUrl)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(aiEngine.isAIProcessing)
                                        .onChange(of: aiEngine.aiApiBaseUrl) { oldValue, newValue in
                                            aiEngine.checkURLSafety(urlString: newValue)
                                        }
                                        .accessibilityLabel("AI 服务端点 URL 输入框")
                                    
                                    if aiEngine.isExternalURLWarning {
                                        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.red)
                                                .font(.system(.caption2))
                                            Text("警示：配置了外部公网 API 地址，您的数据存在泄露风险。")
                                                .font(.system(.caption2))
                                                .foregroundColor(.red)
                                                .lineLimit(2)
                                                .lineSpacing(2)
                                        }
                                        .padding(.top, 2)
                                        .transition(.opacity)
                                    }
                                    
                                    HStack(spacing: Theme.Spacing.sm) {
                                        Button("Ollama") {
                                            aiEngine.aiApiBaseUrl = "http://localhost:11434/v1"
                                            aiEngine.checkURLSafety(urlString: "http://localhost:11434/v1")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(aiEngine.isAIProcessing)
                                        
                                        Button("LM Studio") {
                                            aiEngine.aiApiBaseUrl = "http://localhost:1234/v1"
                                            aiEngine.checkURLSafety(urlString: "http://localhost:1234/v1")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(aiEngine.isAIProcessing)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    HStack {
                                        Text("AI 模型名称")
                                            .font(.system(.caption2, design: .default).weight(.medium))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if aiEngine.isAIFetchingModels {
                                            ProgressView()
                                                .controlSize(.small)
                                                .scaleEffect(0.6)
                                        }
                                    }
                                    
                                    if aiEngine.aiModels.isEmpty {
                                        TextField("如 qwen2.5-7b-instruct", text: $aiEngine.aiSelectedModel)
                                            .textFieldStyle(.roundedBorder)
                                            .disabled(aiEngine.isAIProcessing)
                                            .accessibilityLabel("AI 模型名称文本框")
                                    } else {
                                        Picker("", selection: $aiEngine.aiSelectedModel) {
                                            ForEach(aiEngine.aiModels, id: \.self) { model in
                                                Text(model).tag(model)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .disabled(aiEngine.isAIProcessing)
                                        .frame(maxWidth: .infinity)
                                        .accessibilityLabel("AI 模型选择器")
                                    }
                                    
                                    Button(action: {
                                        aiEngine.fetchAIModels()
                                    }) {
                                        HStack(spacing: Theme.Spacing.xs) {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                            Text("获取本地可用模型")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(aiEngine.isAIProcessing)
                                }
                                
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text("高级净化选项")
                                        .font(.system(.caption2, design: .default).weight(.semibold))
                                        .foregroundColor(.secondary)
                                    
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        Toggle(isOn: $aiShowChanges) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("要求 AI 输出修改留痕")
                                                    .font(.system(.caption, design: .default).weight(.medium))
                                                Text("开启后输出留痕括号，建议参数量较大的本地模型使用。")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .toggleStyle(.checkbox)
                                        .disabled(aiEngine.isAIProcessing)
                                        
                                        Toggle(isOn: $aiPassWatermarks) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("将水印干扰词作为负面词传给 AI")
                                                    .font(.system(.caption, design: .default).weight(.medium))
                                                Text("将识别到或自定义的水印词注入系统指令中，引导针对性清洗。")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .toggleStyle(.checkbox)
                                        .disabled(aiEngine.isAIProcessing)
                                    }
                                    .padding(Theme.Spacing.sm)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                                }
                                .padding(.bottom, Theme.Spacing.sm)

                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text("排版与纠错系统提示词")
                                        .font(.system(.caption2, design: .default).weight(.medium))
                                        .foregroundColor(.secondary)
                                    TextEditor(text: $systemPrompt)
                                        .font(.system(.caption2))
                                        .frame(height: 120)
                                        .padding(3)
                                        .background(Color(nsColor: .textBackgroundColor))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                        )
                                        .disabled(aiEngine.isAIProcessing)
                                        .accessibilityLabel("AI 净化系统提示词编辑框")
                                }
                                
                                if !aiEngine.aiProgressStatus.isEmpty {
                                    Text(aiEngine.aiProgressStatus)
                                        .font(.system(.caption2, design: .default).weight(.medium))
                                        .foregroundColor(.purple)
                                        .lineLimit(2)
                                        .padding(.top, 2)
                                }
                            }
                            .padding(.leading, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                        } label: {
                            Label("本地 AI 净化助手", systemImage: "cpu")
                                .font(.system(.body, design: .default).weight(.bold))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        // 绑定 onChange，让场景卡直接驱动底层提取通道。
        .onChange(of: processingScenario) { oldValue, newValue in
            updateEngineSettings()
        }
        .onAppear {
            updateEngineSettings()
        }
    }
    
    private var scenarioTintColor: Color {
        switch processingScenario {
        case .electronicTextWithTextWatermark:
            return .blue
        case .scannedTextWithTextWatermark:
            return .indigo
        case .fullyScanned:
            return .orange
        }
    }
    
    private var scenarioSymbolName: String {
        switch processingScenario {
        case .electronicTextWithTextWatermark:
            return "doc.text"
        case .scannedTextWithTextWatermark:
            return "doc.viewfinder"
        case .fullyScanned:
            return "scanner"
        }
    }
    
    /// 场景映射逻辑：用户选择真实 PDF 类型后，自动写入底层提取管线。
    private func updateEngineSettings() {
        extractionMode = processingScenario.extractionMode
        watermarkRemovalMode = processingScenario.watermarkRemovalMode
        enableWatermarkFilter = processingScenario.enableWatermarkFilter
    }
}
