import SwiftUI

// MARK: - 标准 macOS 偏好设置窗口 (⌘,)

/// 遵循 Apple HIG 规范的独立设置面板，将全局 AI 模型、提示词与提取偏好从主工作台彻底解耦。
struct SettingsView: View {
    @ObservedObject var aiEngine: AIProcessingEngine
    
    @AppStorage("systemPrompt") private var systemPrompt = AIPromptBuilder.defaultSystemPrompt
    @AppStorage("aiShowChanges") private var aiShowChanges = false
    @AppStorage("aiPassWatermarks") private var aiPassWatermarks = false
    @AppStorage("removeLightWatermarks") private var removeLightWatermarks = true
    @AppStorage("removeColorStamps") private var removeColorStamps = false
    @AppStorage("ignoreCase") private var ignoreCase = true
    
    @AppStorage("settingsSelectedTab") private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 本地 AI 模型服务
            aiModelSettingsTab
                .tabItem {
                    Label("本地 AI 模型", systemImage: "cpu")
                }
                .tag(0)
            
            // Tab 2: 提示词与净化排版
            promptSettingsTab
                .tabItem {
                    Label("提示词与排版", systemImage: "text.badge.sparkles")
                }
                .tag(1)
            
            // Tab 3: 通用与去水印偏好
            generalSettingsTab
                .tabItem {
                    Label("通用偏好", systemImage: "gearshape")
                }
                .tag(2)
        }
        .frame(width: 520, height: 400)
        .padding(Theme.Spacing.lg)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
    
    // MARK: - Tab 1: 本地 AI 模型设置
    private var aiModelSettingsTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("API 服务地址 (OpenAI 兼容)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("http://localhost:11434/v1", text: $aiEngine.aiApiBaseUrl)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: aiEngine.aiApiBaseUrl) { oldValue, newValue in
                            aiEngine.checkURLSafety(urlString: newValue)
                        }
                    
                    if let error = aiEngine.endpointValidationError {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if aiEngine.isExternalURLWarning {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("外部地址可能将数据发送至公网，请谨慎授权。", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Toggle(
                                "允许连接当前外部地址",
                                isOn: Binding(
                                    get: { aiEngine.allowsExternalEndpoint },
                                    set: { aiEngine.setExternalEndpointPermission($0) }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .font(.caption2)
                        }
                    }
                    
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("使用 Ollama (11434)") {
                            aiEngine.aiApiBaseUrl = "http://localhost:11434/v1"
                            aiEngine.checkURLSafety(urlString: "http://localhost:11434/v1")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("使用 LM Studio (1234)") {
                            aiEngine.aiApiBaseUrl = "http://localhost:1234/v1"
                            aiEngine.checkURLSafety(urlString: "http://localhost:1234/v1")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("服务端点")
            }
            
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("API 密钥 (可选，保存在 macOS 钥匙串)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: Theme.Spacing.sm) {
                        SecureField("本地服务通常无需密钥", text: $aiEngine.aiApiKey)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("保存") {
                            aiEngine.saveAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button {
                            aiEngine.clearAPIKey()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(aiEngine.aiApiKey.isEmpty)
                        .help("清除已保存的密钥")
                    }
                }
            } header: {
                Text("凭证管理")
            }
            
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text("当前选定模型")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if aiEngine.isAIFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.6)
                        }
                    }
                    
                    HStack(spacing: Theme.Spacing.sm) {
                        if aiEngine.aiModels.isEmpty {
                            TextField("如 qwen2.5-7b-instruct", text: $aiEngine.aiSelectedModel)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Picker("", selection: $aiEngine.aiSelectedModel) {
                                ForEach(aiEngine.aiModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        
                        Button {
                            aiEngine.fetchAIModels()
                        } label: {
                            Label("刷新模型列表", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("模型选择")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 2: 提示词与净化设置
    private var promptSettingsTab: some View {
        Form {
            Section {
                Toggle("要求 AI 输出修改留痕括号", isOn: $aiShowChanges)
                    .toggleStyle(.checkbox)
                    .help("开启后模型会在修改处标注说明，适合大参数量模型")
                
                Toggle("将检测到的水印词作为负面词传给 AI", isOn: $aiPassWatermarks)
                    .toggleStyle(.checkbox)
                    .help("引导本地模型针对性识别并洗掉特定残留文字")
            } header: {
                Text("高级净化行为")
            }
            
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("默认排版与纠错系统提示词")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $systemPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 140)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                    
                    Button("恢复默认提示词") {
                        systemPrompt = AIPromptBuilder.defaultSystemPrompt
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
                }
            } header: {
                Text("系统指令 (System Prompt)")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 3: 通用偏好
    private var generalSettingsTab: some View {
        Form {
            Section {
                Toggle("默认消除浅色/浅灰背景水印", isOn: $removeLightWatermarks)
                    .toggleStyle(.checkbox)
                    .help("利用 Core Image 智能拉伸图像明度，在 OCR 前洗白浅色杂印")
                
                Toggle("默认滤除红蓝彩色印章", isOn: $removeColorStamps)
                    .toggleStyle(.checkbox)
                    .help("抹平红蓝彩色图层，消除审批章与公章字符对正文 OCR 的粘连干扰")
                
                Toggle("文本去水印默认忽略英文字母大小写", isOn: $ignoreCase)
                    .toggleStyle(.checkbox)
            } header: {
                Text("图像预处理与去水印默认值")
            }
            
            Section {
                HStack {
                    Text("应用版本")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("1.3.0 (macOS 原生架构)")
                        .foregroundStyle(.primary)
                }
                
                HStack {
                    Text("隐私保障")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("100% 本地离线处理，无任何数据上传")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("关于")
            }
        }
        .formStyle(.grouped)
    }
}

#if canImport(PreviewsMacros)
#Preview {
    SettingsView(aiEngine: AIProcessingEngine())
}
#endif
