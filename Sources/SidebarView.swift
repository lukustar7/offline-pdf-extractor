import SwiftUI

// MARK: - 水印风格枚举
enum WatermarkStyle: String, CaseIterable, Identifiable, Codable {
    case none = "无水印"
    case electronic = "活字水印"
    case scan = "扫描件水印"
    
    var id: String { self.rawValue }
}

// MARK: - 内容版式类型枚举
enum ContentType: String, CaseIterable, Identifiable, Codable {
    case electronic = "电子文本"
    case scan = "扫描图像"
    
    var id: String { self.rawValue }
}

// MARK: - 左侧控制侧边栏视图 (macOS 原生 Inspector 风格)
struct SidebarView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @ObservedObject var aiEngine: AIProcessingEngine
    
    @Binding var resultText: String
    @Binding var txtFileURL: URL?
    @Binding var mdFileURL: URL?
    @Binding var selectedTab: Int
    
    // 使用 @AppStorage 对用户偏好进行持久化保存，防止重启丢失配置
    @AppStorage("extractionMode") private var extractionMode: ExtractionMode = .smart
    @AppStorage("watermarkRemovalMode") private var watermarkRemovalMode: WatermarkRemovalMode = .auto
    @AppStorage("enableWatermarkFilter") private var enableWatermarkFilter = true
    @AppStorage("ignoreCase") private var ignoreCase = true
    @AppStorage("eraseImageWatermark") private var eraseImageWatermark = false
    @AppStorage("pageRangeString") private var pageRangeString = ""
    @AppStorage("customWatermarks") private var customWatermarks = ""
    
    // 映射至 SettingSelectorCard 小方块所使用的新 AppStorage 变量
    @AppStorage("watermarkStyle") private var watermarkStyle: WatermarkStyle = .electronic
    @AppStorage("contentType") private var contentType: ContentType = .electronic
    @AppStorage("extractImages") private var extractImages = false
    
    @AppStorage("systemPrompt") private var systemPrompt = """
    你是一个极为严谨的文本排版与错别字纠正助手。你将接收一段由 OCR 引擎从扫描件中识别出的原始文本。
    请执行以下处理：
    1. 保持原文的主体段落结构 and 逻辑含义完全不变，切勿重写、扩写或精简正文内容。
    2. 修复文本中由于 OCR 识别误差导致的可能错字、别字（例如把“而且”识别为“面且”，把“我们”识别为“我门”）。
    3. 智能修复不合理的强行换行：只智能合并由于 OCR 扫描在行尾造成的生硬硬断行（本应是一句话但断开了）。【核心铁律】：严禁将原本属于不同自然段、有空行分隔或语义独立的换行强行合并为一行。必须严格保留原文中所有的自然段落结构！
    4. 【核心铁律】：每当你在排版、硬换行、字词上修改了任何内容，你必须在修改后的内容旁边，紧随其后附上大括号，格式为：“【识别是：[原始错误/硬换行]，修改为：[修改后/合并内容]】”。
    5. 只输出处理纠正后的最终文本，严禁夹带任何多余的开场白、解释、Markdown 标记或总结语！
    """
    
    // 侧边栏当前激活的 Tab：0 -> 提取设置, 1 -> AI 设置
    @State private var activeSidebarTab = 0
    @State private var isSettingsExpanded = true
    @State private var isWatermarkExpanded = true
    @State private var isAIExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            // macOS 侧边栏属性卡片顶部标题，使用标准 Source List Group Header 风格
            HStack {
                Text("配置控制面板")
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
                                Text("加载 PDF 失败")
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
                                    resultText = ""
                                    txtFileURL = nil
                                    mdFileURL = nil
                                    selectedTab = 0
                                }
                            )
                            .padding(.top, Theme.Spacing.sm)
                            
                            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                                // 提取配置折叠组
                                DisclosureGroup(isExpanded: $isSettingsExpanded) {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                        
                                        // 1. 水印样式小方块选择器
                                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                            Text("水印样式")
                                                .font(.system(.caption, design: .default).weight(.semibold))
                                                .foregroundColor(.secondary)
                                            
                                            HStack(spacing: Theme.Spacing.sm) {
                                                SettingSelectorCard(
                                                    title: "纯净无印",
                                                    subTitle: "直接读取，正文 0 误伤",
                                                    isSelected: watermarkStyle == .none,
                                                    action: { watermarkStyle = .none }
                                                )
                                                
                                                SettingSelectorCard(
                                                    title: "活字水印",
                                                    subTitle: "过滤矢量水印，精度高",
                                                    isSelected: watermarkStyle == .electronic,
                                                    action: { watermarkStyle = .electronic }
                                                )
                                                
                                                SettingSelectorCard(
                                                    title: "扫描件水印",
                                                    subTitle: "物理擦除水印并 OCR",
                                                    isSelected: watermarkStyle == .scan,
                                                    action: { watermarkStyle = .scan }
                                                )
                                            }
                                            
                                            // 动态警示气泡
                                            VStack(alignment: .leading, spacing: 0) {
                                                switch watermarkStyle {
                                                case .none:
                                                    Text("💡 PDF 无水印。直接调用原生文字通道，提取精度 100%，正文 0 误伤。")
                                                        .foregroundColor(.blue)
                                                case .electronic:
                                                    Text("💡 电子版水印。系统将精准过滤隐藏的 PDF 水印字符节点，提取精度近乎 100%，正文 0 误伤。")
                                                        .foregroundColor(.green)
                                                case .scan:
                                                    Text("⚠️ 扫描件水印。水印与文字融合于图片背景。系统将调用像素擦除并重新执行 OCR 识字，若水印与正文重叠，可能导致重叠处文字误伤，推荐开启右侧‘AI 净化’进行自动还原。")
                                                        .foregroundColor(.orange)
                                                }
                                            }
                                            .font(.system(.caption2))
                                            .lineSpacing(2)
                                            .padding(Theme.Spacing.sm)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(
                                                        watermarkStyle == .none ? Color.blue.opacity(0.06) :
                                                        (watermarkStyle == .electronic ? Color.green.opacity(0.06) : Color.orange.opacity(0.06))
                                                    )
                                            )
                                            .padding(.top, Theme.Spacing.xs)
                                        }
                                        .padding(.vertical, Theme.Spacing.xs)
                                        
                                        // 2. 正文样式小方块选择器
                                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                            Text("正文样式")
                                                .font(.system(.caption, design: .default).weight(.semibold))
                                                .foregroundColor(.secondary)
                                            
                                            HStack(spacing: Theme.Spacing.sm) {
                                                SettingSelectorCard(
                                                    title: "电子文本",
                                                    subTitle: "排版规范，可直接复制",
                                                    isSelected: contentType == .electronic,
                                                    action: { contentType = .electronic }
                                                )
                                                
                                                SettingSelectorCard(
                                                    title: "扫描图像",
                                                    subTitle: "图片/照片组成，需 OCR",
                                                    isSelected: contentType == .scan,
                                                    action: { contentType = .scan }
                                                )
                                            }
                                        }
                                        .padding(.vertical, Theme.Spacing.xs)
                                        
                                        // 3. 保留正文插图勾选框
                                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                            Toggle("保留正文插图 (提取并导出)", isOn: $extractImages)
                                                .toggleStyle(.checkbox)
                                                .disabled(contentType == .scan)
                                            
                                            if contentType == .scan {
                                                Text("💡 扫描件暂不支持独立插图提取。")
                                                    .font(.system(.caption2))
                                                    .foregroundColor(.secondary.opacity(0.8))
                                            } else {
                                                Text("💡 仅限电子版 PDF，系统会自动将提取的图片导出到目标文件夹。（尚在研发中）")
                                                    .font(.system(.caption2))
                                                    .foregroundColor(.secondary.opacity(0.8))
                                            }
                                        }
                                        .padding(.vertical, Theme.Spacing.xs)
                                        
                                        // 4. 页码范围输入框
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
                                        
                                        // 原本的底层图像区域擦除微调
                                        if watermarkStyle != .none {
                                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                                Toggle("擦除图片中的水印区域", isOn: $eraseImageWatermark)
                                                    .toggleStyle(.checkbox)
                                                
                                                Text("💡 开启该选项会在 OCR 前对水印覆盖的像素点进行强制白化处理，有效避免水印干扰识字。")
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
                                
                                // 5. 水印管理 (只在非“纯净无印”模式下展示，契合用户对于无水印隐藏管理区的交互简化)
                                if watermarkStyle != .none {
                                    DisclosureGroup(isExpanded: $isWatermarkExpanded) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            if engine.watermarkCandidates.isEmpty {
                                                Text("未检测到高频活字水印。")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                    .padding(.vertical, Theme.Spacing.xs)
                                            } else {
                                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                                    Text("高频疑似水印词:")
                                                        .font(.system(.caption, design: .default).weight(.semibold))
                                                        .foregroundColor(.secondary)
                                                    Text("💡 以下词汇因在多页中重复出现，系统初步判定其为水印。如果其中包含正文字词，请取消勾选以防止误删。")
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
                                                Text("手动添加过滤词 (逗号或换行隔开):")
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
                                        Label("活字水印过滤管理", systemImage: "tag")
                                            .font(.system(.body, design: .default).weight(.bold))
                                            .foregroundColor(.primary)
                                    }
                                    .transition(.opacity)
                                }
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
                                        .onChange(of: aiEngine.aiApiBaseUrl) { newValue in
                                            aiEngine.checkURLSafety(urlString: newValue)
                                        }
                                        .accessibilityLabel("AI 服务端点 URL 输入框")
                                    
                                    if aiEngine.isExternalURLWarning {
                                        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.red)
                                                .font(.system(.caption2))
                                            Text("⚠️ 警示：配置了外部公网 API 地址，您的数据存在泄露风险！")
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
        // 绑定 onChange，在卡片样式发生交互点击时，后台无缝自动更新底层引擎字段
        .onChange(of: watermarkStyle) { _ in
            updateEngineSettings()
        }
        .onChange(of: contentType) { _ in
            updateEngineSettings()
        }
        .onAppear {
            updateEngineSettings()
        }
    }
    
    /// 双向映射逻辑：在用户点击小方块卡片交互时，后台智能重置底层引擎去水印和提取通道选项
    private func updateEngineSettings() {
        switch watermarkStyle {
        case .none:
            enableWatermarkFilter = false
        case .electronic:
            enableWatermarkFilter = true
            watermarkRemovalMode = .modeA
        case .scan:
            enableWatermarkFilter = true
            watermarkRemovalMode = .modeC
        }
        
        switch contentType {
        case .electronic:
            extractionMode = .textOnly
        case .scan:
            extractionMode = .ocrOnly
        }
    }
}
