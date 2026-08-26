import SwiftUI

// MARK: - 标准 macOS 偏好设置窗口 (⌘,) (Liquid Glass 全透毛玻璃 + 现代大方 Segmented 标签栏)

struct SettingsView: View {
    @ObservedObject var aiEngine: AIProcessingEngine
    
    @AppStorage("systemPrompt") private var systemPrompt = AIPromptBuilder.defaultSystemPrompt
    @AppStorage("aiShowChanges") private var aiShowChanges = false
    @AppStorage("aiPassWatermarks") private var aiPassWatermarks = false
    @AppStorage("removeLightWatermarks") private var removeLightWatermarks = true
    @AppStorage("removeColorStamps") private var removeColorStamps = false
    @AppStorage("ignoreCase") private var ignoreCase = true
    @AppStorage("settingsSelectedTab") private var selectedTab = 0
    
    enum SettingsTab: Int, CaseIterable, Identifiable {
        case aiModel = 0
        case prompts = 1
        case general = 2
        
        var id: Int { rawValue }
        
        var title: String {
            switch self {
            case .aiModel: return "AI 模型"
            case .prompts: return "提示词"
            case .general: return "通用偏好"
            }
        }
        
        var icon: String {
            switch self {
            case .aiModel: return "cpu"
            case .prompts: return "text.badge.sparkles"
            case .general: return "gearshape"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部现代 Liquid Glass 悬浮 Segmented 标签栏 (彻底消除 Tab 栏错位挤压)
            HStack {
                Spacer()
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .tag(tab.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .frame(width: 320)
                Spacer()
            }
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
            
            Divider()
            
            // 内容区域
            ZStack {
                switch selectedTab {
                case 0:
                    aiModelSettingsTab
                case 1:
                    promptSettingsTab
                default:
                    generalSettingsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 440)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
    
    // MARK: - Tab 1: 本地 AI 模型设置 (两列工整网格)
    private var aiModelSettingsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // 快速预设填入胶囊
            HStack(spacing: Theme.Spacing.sm) {
                Spacer()
                Text("快捷填入:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Ollama") {
                    aiEngine.aiApiBaseUrl = "http://localhost:11434/v1"
                    aiEngine.fetchAIModels()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("LM Studio") {
                    aiEngine.aiApiBaseUrl = "http://localhost:1234/v1"
                    aiEngine.fetchAIModels()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            
            // 两列工整排版
            VStack(spacing: Theme.Spacing.md) {
                // 行 1: API 服务端点
                settingRow(label: "服务端点:") {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("http://localhost:11434/v1", text: $aiEngine.aiApiBaseUrl)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.regular)
                            .font(.system(size: 12))
                            .onChange(of: aiEngine.aiApiBaseUrl) { oldValue, newValue in
                                aiEngine.checkURLSafety(urlString: newValue)
                            }
                        
                        if let error = aiEngine.endpointValidationError {
                            Label(error, systemImage: "xmark.octagon.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        } else if aiEngine.isExternalURLWarning {
                            Toggle(
                                "我已了解风险，允许连接公网端点",
                                isOn: Binding(
                                    get: { aiEngine.allowsExternalEndpoint },
                                    set: { aiEngine.setExternalEndpointPermission($0) }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        }
                    }
                }
                
                // 行 2: 模型选择 + 等高正方形刷新按钮 [ 🔄 ]
                settingRow(label: "选择模型:") {
                    HStack(spacing: Theme.Spacing.xs) {
                        if aiEngine.aiModels.isEmpty {
                            TextField("直接输入模型名，如 qwen2.5:7b", text: $aiEngine.aiSelectedModel)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.regular)
                                .font(.system(size: 12))
                        } else {
                            Picker("", selection: $aiEngine.aiSelectedModel) {
                                ForEach(aiEngine.aiModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.regular)
                        }
                        
                        Button {
                            aiEngine.fetchAIModels()
                        } label: {
                            if aiEngine.isAIFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .frame(width: 28, height: 28)
                        .help("刷新本地服务的可用模型列表")
                    }
                }
                
                // 行 3: API Key
                settingRow(label: "API 密钥 (可选):") {
                    SecureField("本地 Ollama 可留空", text: $aiEngine.aiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                        .font(.system(size: 12))
                        .onChange(of: aiEngine.aiApiKey) { oldValue, newValue in
                            aiEngine.saveAPIKey()
                        }
                }
            }
            
            Spacer()
            
            // 底部安全合规可信说明
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.tint)
                Text("所有 API 密钥均安全加密存储于 macOS 系统钥匙串 (Keychain)。本地端点处理绝不上云。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.sm)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .liquidGlassBorder(cornerRadius: Theme.Radius.sm)
        }
        .padding(Theme.Spacing.lg)
    }
    
    // MARK: - Tab 2: 提示词与净化排版设置
    private var promptSettingsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            settingRow(label: "系统 Prompt:") {
                TextEditor(text: $systemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 140)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    .liquidGlassBorder(cornerRadius: Theme.Radius.sm)
            }
            
            settingRow(label: "标识变动:") {
                Toggle(isOn: $aiShowChanges) {
                    Text("以 Markdown 粗体高亮 AI 修正的错字")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
            
            settingRow(label: "传递水印列表:") {
                Toggle(isOn: $aiPassWatermarks) {
                    Text("将文档中的水印词作为负向词传给 AI 指令")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("恢复默认 Prompt") {
                    systemPrompt = AIPromptBuilder.defaultSystemPrompt
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(Theme.Spacing.lg)
    }
    
    // MARK: - Tab 3: 通用与去水印偏好设置
    private var generalSettingsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            settingRow(label: "色阶去水印:") {
                Toggle(isOn: $removeLightWatermarks) {
                    Text("Core Image 智能拉伸明度抹白浅灰水印 (默认开启)")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
            
            settingRow(label: "大小写敏感:") {
                Toggle(isOn: $ignoreCase) {
                    Text("水印词匹配时忽略英文字母大小写")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
            
            settingRow(label: "应用版本:") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("v1.3.0 (Liquid Glass Release)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("已是最新稳定版本。所有文字提取与去水印滤镜均完全离线安全运行。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }
    
    // MARK: - 两列对齐辅助组件
    private func settingRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
                .padding(.top, 4)
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
