import SwiftUI

// MARK: - 左侧控制侧边栏视图
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
    @AppStorage("systemPrompt") private var systemPrompt = """
你是一个极为严谨的文本排版与错别字纠正助手。你将接收一段由 OCR 引擎从扫描件中识别出的原始文本。
请执行以下处理：
1. 保持原文的主体段落结构和逻辑含义完全不变，切勿重写、扩写或精简正文内容。
2. 修复文本中由于 OCR 识别误差导致的可能错字、别字（例如把“而且”识别为“面且”，把“我们”识别为“我门”）。
3. 智能修复不合理的强行换行：只智能合并由于 OCR 扫描在行尾造成的生硬硬断行（本应是一句话但断开了）。【核心铁律】：严禁将原本属于不同自然段、有空行分隔或语义独立的换行强行合并为一行。必须严格保留原文中所有的自然段落结构！
4. 【核心铁律】：每当你在排版、硬换行、字词上修改了任何内容，你必须在修改后的内容旁边，紧随其后附上大括号，格式为：“【识别是：[原始错误/硬换行]，修改为：[修改后/合并内容]】”。
例如：如果原文是“面且我门要\n去公园”，纠正后应输出：“而且【识别是：面且，修改为：而且】我们【识别是：我门，修改为：我们】要去公园【识别是：要\n去，修改为：要去】”。
5. 只输出处理纠正后的最终文本，严禁夹带任何多余的开场白、解释、Markdown 标记或总结语！
"""
    
    @State private var dragOver = false
    @State private var isSettingsExpanded = true
    @State private var isWatermarkExpanded = true
    @State private var isAIExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题与 App 品牌
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("PDF 本地去水印")
                        .font(.system(size: 16, weight: .bold))
                    Text("100% 离线文字提取与 AI 净化")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
                .padding(.horizontal, 16)
            
            // 可滚动控制面板列表
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    
                    // 1. 文件导入卡片
                    if engine.pdfFileName.isEmpty {
                        DropZoneView(isDragOver: $dragOver) { url in
                            _ = engine.loadPDF(url: url)
                        }
                        .padding(.top, 10)
                    } else {
                        FileInfoView(
                            name: engine.pdfFileName,
                            size: engine.pdfFileSize,
                            pages: engine.pdfTotalPages,
                            onClear: {
                                engine.clear()
                                resultText = ""
                                txtFileURL = nil
                                mdFileURL = nil
                                selectedTab = 0
                            }
                        )
                        .padding(.top, 10)
                    }
                    
                    if !engine.pdfFileName.isEmpty {
                        // 2. 提取配置
                        VStack(alignment: .leading, spacing: 0) {
                            Button(action: { withAnimation { isSettingsExpanded.toggle() } }) {
                                HStack {
                                    Text("提取设置")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Image(systemName: isSettingsExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            
                            if isSettingsExpanded {
                                VStack(alignment: .leading, spacing: 10) {
                                    // 提取模式单选
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("提取通道")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        
                                        Picker("", selection: $extractionMode) {
                                            ForEach(ExtractionMode.allCases) { mode in
                                                Text(mode.rawValue).tag(mode)
                                            }
                                        }
                                        .pickerStyle(.radioGroup)
                                        .horizontalRadioLayout()
                                    }
                                    
                                    // 全局去水印识别总控开关
                                    Toggle("开启水印过滤与像素擦除", isOn: $enableWatermarkFilter)
                                        .toggleStyle(.checkbox)
                                        .font(.system(size: 11, weight: .semibold))
                                    
                                    if enableWatermarkFilter {
                                        // 专属去水印场景模式选择
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("去水印工作模式:")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                            
                                            Picker("", selection: $watermarkRemovalMode) {
                                                ForEach(WatermarkRemovalMode.allCases) { mode in
                                                    Text(mode.rawValue).tag(mode)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                            
                                            // 针对三种具体情况的算法说明
                                            Group {
                                                switch watermarkRemovalMode {
                                                case .auto:
                                                    Text("💡 [智能诊断] 系统将自动判断页面的文字与扫描图片比例，自动选择最佳去水印算法。")
                                                case .modeA:
                                                    Text("💡 [模式 A] 正文和水印皆可选中。系统在提取时精准跳过水印节点，不跑 OCR，极速且 0 误杀。")
                                                case .modeB:
                                                    Text("💡 [模式 B] 正文是扫描图片且水印文字可选中。系统先对水印坐标进行像素抹白，再对干净页面进行 OCR 识别。")
                                                case .modeC:
                                                    Text("⚠️ [模式 C] 扫描件水印。正文和水印都已印在纸张上（不可选中）。系统将整体 OCR 后过滤字符。提示：若水印遮挡正文笔画，可能轻微影响重叠区域的 OCR 识别率，推荐配合“本地 AI 净化”以达到最佳效果。")
                                                        .foregroundColor(.orange)
                                                }
                                            }
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineSpacing(2)
                                            .padding(.top, 2)
                                        }
                                        .transition(.opacity)
                                    }
                                    
                                    // 页码范围选择
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("指定提取页码范围 (如 1-5, 8, 10-12):")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        TextField("留空则提取全部页面", text: $pageRangeString)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11))
                                    }
                                    .padding(.vertical, 2)
                                    
                                    Toggle("忽略字母大小写", isOn: $ignoreCase)
                                        .toggleStyle(.checkbox)
                                    
                                    if enableWatermarkFilter {
                                        Toggle("擦除图片中的水印区域", isOn: $eraseImageWatermark)
                                            .toggleStyle(.checkbox)
                                        
                                        Text("💡 默认通过后处理技术无损净化水印。若水印字词严重重叠遮挡了文字识别，可开启上面选项进行像素擦除。")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineSpacing(2)
                                    }
                                }
                                .padding(.top, 8)
                                .padding(.bottom, 12)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(12)
                        
                        // 3. 水印管理
                        if enableWatermarkFilter {
                            VStack(alignment: .leading, spacing: 0) {
                                Button(action: { withAnimation { isWatermarkExpanded.toggle() } }) {
                                    HStack {
                                        Text("活字水印过滤管理")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Image(systemName: isWatermarkExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                
                                if isWatermarkExpanded {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if engine.watermarkCandidates.isEmpty {
                                            Text("未检测到高频活字水印。")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .padding(.vertical, 4)
                                        } else {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("系统识别疑似水印")
                                                    .font(.system(size: 11, weight: .bold))
                                                Text("💡 以下词汇因在多页中重复出现，系统初步判定其为水印。如果其中包含正文字词，请取消勾选以防止误删。")
                                                    .font(.system(size: 9.5))
                                                    .foregroundColor(.secondary)
                                                    .lineSpacing(2)
                                            }
                                            .padding(.bottom, 4)
                                            
                                            // 修复 ForEach 下标越界 Crash：改用基于 Collection Element 的安全绑定迭代，杜绝崩溃
                                            ForEach($engine.watermarkCandidates) { $candidate in
                                                Toggle(isOn: $candidate.isSelected) {
                                                    HStack {
                                                        Text(candidate.text)
                                                            .font(.system(size: 11.5, weight: .medium))
                                                            .lineLimit(1)
                                                        Spacer()
                                                        Text("\(candidate.occurrenceCount) 页")
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                .toggleStyle(.checkbox)
                                            }
                                        }
                                        
                                        Divider()
                                            .padding(.vertical, 4)
                                        
                                        Text("手动添加过滤词（逗号或换行隔开）:")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                        
                                        TextEditor(text: $customWatermarks)
                                            .font(.system(.body, design: .default))
                                            .frame(height: 50)
                                            .padding(4)
                                            .background(Color(nsColor: .textBackgroundColor))
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                            )
                                    }
                                    .padding(.top, 8)
                                    .padding(.bottom, 12)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .cornerRadius(12)
                            .transition(.opacity)
                        }
                        
                        // 4. 本地 AI 推理设置
                        VStack(alignment: .leading, spacing: 0) {
                            Button(action: { withAnimation { isAIExpanded.toggle() } }) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "cpu.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.purple)
                                        Text("本地 AI 净化助手")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: isAIExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            
                            if isAIExpanded {
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("API 服务地址:")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        TextField("http://localhost:11434/v1", text: $aiEngine.aiApiBaseUrl)
                                            .textFieldStyle(.roundedBorder)
                                            .disabled(aiEngine.isAIProcessing)
                                            .onChange(of: aiEngine.aiApiBaseUrl) { newValue in
                                                aiEngine.checkURLSafety(urlString: newValue)
                                            }
                                        
                                        if aiEngine.isExternalURLWarning {
                                            HStack(alignment: .top, spacing: 4) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundColor(.red)
                                                    .font(.system(size: 10))
                                                Text("⚠️ 警示：配置了外部公网 API 地址，您的数据存在泄露风险！")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.red)
                                                    .lineLimit(2)
                                                    .lineSpacing(2)
                                            }
                                            .padding(.top, 2)
                                            .transition(.opacity)
                                        }
                                        
                                        HStack(spacing: 8) {
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
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("AI 模型名称:")
                                                .font(.system(size: 10))
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
                                        } else {
                                            Picker("选择模型", selection: $aiEngine.aiSelectedModel) {
                                                ForEach(aiEngine.aiModels, id: \.self) { model in
                                                    Text(model).tag(model)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                            .disabled(aiEngine.isAIProcessing)
                                        }
                                        
                                        Button(action: {
                                            aiEngine.fetchAIModels()
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.triangle.2.circlepath")
                                                Text("获取本地可用模型")
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(aiEngine.isAIProcessing)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("排版与纠错系统提示词:")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        TextEditor(text: $systemPrompt)
                                            .font(.system(size: 9.5))
                                            .frame(height: 70)
                                            .padding(3)
                                            .background(Color(nsColor: .textBackgroundColor))
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                            )
                                            .disabled(aiEngine.isAIProcessing)
                                    }
                                    
                                    if !aiEngine.aiProgressStatus.isEmpty {
                                        Text(aiEngine.aiProgressStatus)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.purple)
                                            .lineLimit(2)
                                            .padding(.top, 2)
                                    }
                                }
                                .padding(.top, 8)
                                .padding(.bottom, 12)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            
            Spacer()
            
            // 底部触发按钮
            if !engine.pdfFileName.isEmpty && !engine.isProcessing {
                VStack(spacing: 8) {
                    Button(action: startExtractionAction) {
                        HStack(spacing: 8) {
                            if engine.isAnalyzingWatermarks {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                                    .brightness(0.5)
                                Text("正在自动分析水印词...")
                            } else {
                                Text("开始提取文字")
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            engine.isAnalyzingWatermarks ?
                            AnyShapeStyle(Color.gray.opacity(0.4)) :
                            AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                        )
                        .cornerRadius(8)
                        .shadow(color: engine.isAnalyzingWatermarks ? Color.clear : Color.purple.opacity(0.2), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(aiEngine.isAIProcessing || engine.isAnalyzingWatermarks)
                    
                    if !resultText.isEmpty && !aiEngine.isAIProcessing {
                        Button(action: startAIProcessingAction) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("发送至本地 AI 净化")
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(8)
                            .shadow(color: Color.pink.opacity(0.25), radius: 5, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 320) // 默认宽度限制，由外部 HSplitView 允许拖拽拉伸
    }
    
    /// 开始文字提取核心逻辑
    private func startExtractionAction() {
        let active = Set(engine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
        engine.extractText(
            activeWatermarks: active,
            customWatermarks: customWatermarks,
            ignoreCase: ignoreCase,
            mode: extractionMode,
            watermarkRemovalMode: watermarkRemovalMode,
            enableWatermarkFilter: enableWatermarkFilter,
            eraseImageWatermark: eraseImageWatermark,
            pageRangeString: pageRangeString
        ) { result, url, mdUrl, avgTime in
            self.resultText = result
            self.txtFileURL = url
            self.mdFileURL = mdUrl
            // 跳转至“原始提取文本”Tab (索引为 0)
            withAnimation {
                self.selectedTab = 0
            }
        }
    }
    
    /// 发送给 AI 纠错净化
    private func startAIProcessingAction() {
        // 跳转至“AI 净化”Tab (索引为 1)
        withAnimation {
            self.selectedTab = 1
        }
        aiEngine.processTextWithAI(
            inputText: resultText,
            systemPrompt: systemPrompt,
            fileURL: engine.pdfURL
        )
    }
}

// MARK: - SwiftUI RadioButton picker layout helper
extension View {
    func horizontalRadioLayout() -> some View {
        self.modifier(HorizontalRadioStyleModifier())
    }
}

struct HorizontalRadioStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .labelsHidden()
            .padding(.vertical, 4)
    }
}
