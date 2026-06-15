import SwiftUI

// MARK: - 左侧控制侧边栏视图 (macOS 原生 Form 风格)
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
        VStack(spacing: 0) {
            // macOS 侧边栏属性卡片顶部标题，使用标准 Source List Group Header 风格
            HStack {
                Text("提取与过滤设置")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 12)
            
            // 纯净的 ScrollView + Form，完全采用 macOS 系统默认排版比例
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    
                    // 1. 拖拽文件状态展示
                    if engine.pdfFileName.isEmpty {
                        DropZoneView(isDragOver: $dragOver) { url in
                            _ = engine.loadPDF(url: url)
                        }
                        .padding(.top, 8)
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
                        .padding(.top, 8)
                    }
                    
                    if !engine.pdfFileName.isEmpty {
                        Form {
                            // 2. 提取参数设置
                            DisclosureGroup(isExpanded: $isSettingsExpanded) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Picker("提取通道:", selection: $extractionMode) {
                                        ForEach(ExtractionMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                    Toggle("启用水印过滤机制", isOn: $enableWatermarkFilter)
                                        .toggleStyle(.checkbox)
                                        .font(.system(size: 11, weight: .medium))
                                    
                                    if enableWatermarkFilter {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Picker("去水印工作模式:", selection: $watermarkRemovalMode) {
                                                ForEach(WatermarkRemovalMode.allCases) { mode in
                                                    Text(mode.rawValue).tag(mode)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            
                                            // 模式简要功能提示，特别是第三个
                                            Group {
                                                switch watermarkRemovalMode {
                                                case .auto:
                                                    Text("💡 系统将智能检测文件类型并自动在 A/B/C 三种算法中派发。")
                                                case .modeA:
                                                    Text("💡 纯文本去水印（文字版 PDF）。直接过滤倾斜的水印文本节点，不跑 OCR，极速且不伤正文。")
                                                case .modeB:
                                                    Text("💡 物理遮罩 + OCR（扫描件 + 文字水印）。先获取水印矢量坐标并用白色擦除，再对干净页面执行 OCR。")
                                                case .modeC:
                                                    Text("⚠️ OCR + 智能过滤（纯扫描件水印）。正文与水印均印在纸张上（不可选中）。系统将整体 OCR 后过滤字符。提示：若水印遮挡正文笔画，可能轻微影响重叠区域的识字率，推荐配合“本地 AI 净化”以达到最佳效果。")
                                                        .foregroundColor(.orange)
                                                }
                                            }
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineSpacing(2.5)
                                            .padding(.leading, 8)
                                        }
                                        .transition(.opacity)
                                    }
                                    
                                    TextField("指定页码范围:", text: $pageRangeString)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11))
                                        .help("留空则提取全部页面。支持格式：1-5, 8, 10-12")
                                    
                                    Toggle("忽略字母大小写", isOn: $ignoreCase)
                                        .toggleStyle(.checkbox)
                                    
                                    if enableWatermarkFilter {
                                        Toggle("擦除图片中的水印区域", isOn: $eraseImageWatermark)
                                            .toggleStyle(.checkbox)
                                        
                                        Text("💡 开启该选项会在 OCR 前对水印覆盖的像素点进行强制白化处理，有效避免水印笔画干扰 OCR 引擎识字。")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineSpacing(2)
                                            .padding(.leading, 8)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("提取配置")
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                            
                            // 3. 水印管理
                            if enableWatermarkFilter {
                                DisclosureGroup(isExpanded: $isWatermarkExpanded) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if engine.watermarkCandidates.isEmpty {
                                            Text("未检测到高频活字水印。")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .padding(.vertical, 4)
                                        } else {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("高频疑似水印词:")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(.secondary)
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
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("手动添加过滤词:")
                                                .font(.system(size: 10))
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
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "tag")
                                        Text("活字水印过滤管理")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                }
                                .transition(.opacity)
                            }
                            
                            // 4. 本地 AI 推理设置
                            DisclosureGroup(isExpanded: $isAIExpanded) {
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
                                            Picker("", selection: $aiEngine.aiSelectedModel) {
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
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "cpu")
                                    Text("本地 AI 净化助手")
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
    }
}
