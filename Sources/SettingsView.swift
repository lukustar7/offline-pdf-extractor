import SwiftUI

// MARK: - 标准 macOS 偏好设置窗口 (⌘,) (Liquid Glass 全透毛玻璃 + 现代大方 Segmented 标签栏)

struct SettingsView: View {
    @AppStorage("removeLightWatermarks") private var removeLightWatermarks = true
    @AppStorage("removeColorStamps") private var removeColorStamps = false
    @AppStorage("ignoreCase") private var ignoreCase = true
    @AppStorage("preserveImages") private var preserveImages = true
    @AppStorage("docxImageScale") private var docxImageScale = 1.0
    @AppStorage("settingsSelectedTab") private var selectedTab = 0
    
    enum SettingsTab: Int, CaseIterable, Identifiable {
        case export = 0
        case filters = 1
        case privacy = 2
        
        var id: Int { rawValue }
        
        var title: String {
            switch self {
            case .export: return "导出与插图"
            case .filters: return "图像与去水印"
            case .privacy: return "隐私与关于"
            }
        }
        
        var icon: String {
            switch self {
            case .export: return "doc.richtext"
            case .filters: return "wand.and.stars"
            case .privacy: return "lock.shield"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部现代 Liquid Glass 悬浮 Segmented 标签栏
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
                .frame(width: 360)
                Spacer()
            }
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
            
            Divider()
            
            // 内容区域
            ZStack {
                switch selectedTab {
                case 0:
                    exportSettingsTab
                case 1:
                    filterSettingsTab
                default:
                    privacySettingsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 380)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
    
    // MARK: - Tab 1: 导出与插图设置
    private var exportSettingsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            settingRow(label: "文档默认格式:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Microsoft Word 文档 (.docx)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("纯本地生成标准 Office Open XML 文件，内嵌高保真插图与排版样式，双击开箱即用。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            settingRow(label: "插图保留与提取:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $preserveImages) {
                        Text("自动定位并截取插图与图表")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                    
                    Text("无论是原装电子版内嵌图片，还是扫描件中的插图与表格，均按阅读顺序自然插入段落间。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            settingRow(label: "段落回车重构:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("智能连贯段落重组已默认启用")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("自动识别并合并因 PDF 页面排版造成的生硬换行，中英文智能分词补空，还原自然段落。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }
    
    // MARK: - Tab 2: 图像与去水印偏好
    private var filterSettingsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            settingRow(label: "色阶抹白去水印:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $removeLightWatermarks) {
                        Text("Core Image 智能拉伸明度抹白浅灰水印 (推荐)")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                    
                    Text("通过底图色阶对比度动态拉伸，抹除文档背景中的浅灰水印网格与底纹，不伤正文墨迹。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            settingRow(label: "彩色印章过滤:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $removeColorStamps) {
                        Text("红通道亮度提取过滤红色公章与彩色图章")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                    
                    Text("在 OCR 识别前利用红通道高穿透性淡化红色印章，大幅提升印章覆盖下文字的识别率。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            settingRow(label: "水印词匹配:") {
                Toggle(isOn: $ignoreCase) {
                    Text("水印排除词过滤时忽略英文字母大小写")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
            
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }
    
    // MARK: - Tab 3: 隐私与关于
    private var privacySettingsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            settingRow(label: "隐私与安全:") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 14))
                        Text("100% 纯本地离线安全架构")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("本应用彻底移除了所有网络请求与外部大模型依赖。代码不包含任何网络连接声明，所有文本识别、图像分析与 Word 导出均在您的 Mac 本地芯片上极速完成，商业机密与个人文档永不出境。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }
            
            settingRow(label: "应用版本:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PDF 文字提取 v1.6.0")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("纯血 Apple Silicon (M系列芯片) 深度调优，三大处理模式横排自选，支持 Word (.docx) 单文件无损直出。")
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
                .frame(width: 120, alignment: .trailing)
                .padding(.top, 2)
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
