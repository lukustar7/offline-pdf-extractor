import SwiftUI

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
            
            // 纯净的 ScrollView + VStack 纵向对齐，摒弃 Form 的双栏拉扯与背景重合
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // 1. 拖拽文件状态展示
                    if engine.pdfFileName.isEmpty {
                        DropZoneView(
                            isDragOver: $dragOver,
                            onFileDropped: { url in
                                engine.loadPDF(url: url)
                            },
                            onInvalidFileDropped: {
                                engine.errorMessage = "仅支持导入 PDF 格式的文件。"
                            }
                        )
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
                        VStack(alignment: .leading, spacing: 14) {
                            
                            // 2. 提取配置
                            DisclosureGroup(isExpanded: $isSettingsExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
                                    // 提取通道 (标签在上，控件在下，宽度 100%)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("提取通道")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                        
                                        Picker("", selection: $extractionMode) {
                                            ForEach(ExtractionMode.allCases) { mode in
                                                Text(mode.rawValue).tag(mode)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .frame(maxWidth: .infinity)
                                    }
                                    
                                    // 全局去水印开关
                                    Toggle("启用水印过滤与像素擦除", isOn: $enableWatermarkFilter)
                                        .toggleStyle(.checkbox)
                                        .font(.system(size: 11, weight: .semibold))
                                    
                                    if enableWatermarkFilter {
                                        // 专属去水印模式
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("去水印工作模式")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.secondary)
                                            
                                            Picker("", selection: $watermarkRemovalMode) {
                                                ForEach(WatermarkRemovalMode.allCases) { mode in
                                                    Text(mode.rawValue).tag(mode)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                            .frame(maxWidth: .infinity)
                                            
                                            // 模式简要说明气泡框
                                            VStack(alignment: .leading, spacing: 4) {
                                                switch watermarkRemovalMode {
                                                case .auto:
                                                    Text("💡 系统将智能分析页面文字比例，自动在 A/B/C 三种算法中调度。")
                                                case .modeA:
                                                    Text("💡 [模式 A] 纯文本去水印。直接过滤倾斜的水印文本节点，不跑 OCR，极速且不伤正文。")
                                                case .modeB:
                                                    Text("💡 [模式 B] 物理遮罩。先获取水印字符矢量坐标并抹白，再对干净页面执行 OCR。")
                                                case .modeC:
                                                    Text("⚠️ [模式 C] 扫描件水印。正文与水印融于背景。整体 OCR 后以字符替换。若水印遮挡正文，可能轻微影响重叠处 OCR 识别率，推荐开启“AI 净化”。")
                                                        .foregroundColor(.orange)
                                                }
                                            }
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineSpacing(3)
                                            .padding(8)
                                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                            .cornerRadius(6)
                                        }
                                        .transition(.opacity)
                                    }
                                    
                                    // 页码范围
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("指定提取页码范围 (如 1-5, 8, 10-12)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                        
                                        TextField("留空则提取全部页面", text: $pageRangeString)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11))
                                    }
                                    
                                    Toggle("忽略字母大小写", isOn: $ignoreCase)
                                        .toggleStyle(.checkbox)
                                    
                                    if enableWatermarkFilter {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Toggle("擦除图片中的水印区域", isOn: $eraseImageWatermark)
                                                .toggleStyle(.checkbox)
                                            
                                            Text("💡 开启该选项会在 OCR 前对水印覆盖的像素点进行强制白化处理，有效避免水印干扰识字。")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                                .lineSpacing(2)
                                        }
                                    }
                                }
                                .padding(.leading, 12)
                                .padding(.vertical, 8)
                            } label: {
                                Label("提取配置", systemImage: "slider.horizontal.3")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                            
                            Divider()
                                .padding(.horizontal, 4)
                            
                            // 3. 水印管理
                            if enableWatermarkFilter {
                                DisclosureGroup(isExpanded: $isWatermarkExpanded) {
                                    VStack(alignment: .leading, spacing: 10) {
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
                                            
                                            // 采用安全的绑定，绝不越界崩溃
                                            ForEach($engine.watermarkCandidates) { $candidate in
                                                Toggle(isOn: $candidate.isSelected) {
                                                    HStack {
                                                        Text(candidate.text)
                                                            .font(.system(size: 11, weight: .medium))
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
                                            Text("手动添加过滤词 (逗号或换行隔开):")
                                                .font(.system(size: 10, weight: .medium))
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
                                    .padding(.leading, 12)
                                    .padding(.vertical, 8)
                                } label: {
                                    Label("活字水印过滤管理", systemImage: "tag")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.primary)
                                }
                                .transition(.opacity)
                                
                                Divider()
                                    .padding(.horizontal, 4)
                            }
                            
                            // 4. 本地 AI 推理设置
                            DisclosureGroup(isExpanded: $isAIExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
                                    // API 地址
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("API 服务地址")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                        
                                        TextField("http://localhost:11434/v1", text: $aiEngine.aiApiBaseUrl)
                                            .textFieldStyle(.roundedBorder)
                                            .disabled(aiEngine.isAIProcessing)
                                            .onChangeCompatible(of: aiEngine.aiApiBaseUrl) { newValue in
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
                                    
                                    // 模型选择
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("AI 模型名称")
                                                .font(.system(size: 10, weight: .medium))
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
                                            .frame(maxWidth: .infinity)
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
                                    
                                    // 提示词
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("排版与纠错系统提示词")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                        TextEditor(text: $systemPrompt)
                                            .font(.system(size: 9.5))
                                            .frame(height: 120)
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
                                .padding(.leading, 12)
                                .padding(.vertical, 8)
                            } label: {
                                Label("本地 AI 净化助手", systemImage: "cpu")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
    }
}

// MARK: - 兼容老版本 macOS 的 onChange 修饰符扩展
extension View {
    /// 兼容 macOS 14.0+ 与更早版本的 onChange 修饰符
    /// - Parameters:
    ///   - value: 要监听的绑定值
    ///   - action: 发生变化时的回调，接收变化后的新值
    @ViewBuilder
    func onChangeCompatible<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            // macOS 14+ 使用新的 closure 接收 (old, new)
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            // macOS 13 及更低版本使用原生的 onChange(of:perform:)
            self.onChange(of: value, perform: action)
        }
    }
}
