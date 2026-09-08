import SwiftUI

// MARK: - 首次启动欢迎开屏视图 (macOS 原生 Onboarding / Welcome Sheet)
/// 遵循 Apple HIG 规范，在新用户首次启动或点击“帮助 -> 欢迎使用”时展示核心功能与隐私承诺。
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasShownWelcomeSheet") private var hasShownWelcomeSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部大图标与欢迎主标题
            VStack(spacing: Theme.Spacing.sm) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                }
                
                Text("欢迎使用 PDF 文字提取")
                    .font(.system(.title, design: .default).weight(.bold))
                    .padding(.top, Theme.Spacing.xs)
                
                Text("macOS 原生离线 · 图文插图留存 · 隐私安全闭环")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.lg)
            
            Divider()
                .padding(.horizontal, Theme.Spacing.xl)
            
            // 中间核心特性列表 (Feature Rows)
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                FeatureRow(
                    icon: "bolt.badge.checkmark.fill",
                    tint: .orange,
                    title: "高精度离线 Vision OCR",
                    description: "采用 macOS 原生视觉引擎，无需连网，离线毫秒级提取扫描件文本。"
                )
                
                FeatureRow(
                    icon: "wand.and.stars",
                    tint: .blue,
                    title: "Core Image 滤镜去水印",
                    description: "红通道消除彩色公章，智能拉伸明度洗白浅灰背景水印与底纹。"
                )
                
                FeatureRow(
                    icon: "doc.richtext.fill",
                    tint: .indigo,
                    title: "Word (.docx) 图文导出",
                    description: "自动定位截取插图，按阅读顺序内嵌于单个 Word 文档中，支持直接编辑。"
                )
                
                FeatureRow(
                    icon: "lock.shield.fill",
                    tint: .green,
                    title: "100% 本地隐私安全",
                    description: "文档解析、文字提取、插图截取与文档导出均在本地设备运行，数据绝不上云。"
                )
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.lg)
            
            Divider()
                .padding(.horizontal, Theme.Spacing.xl)
            
            // 底部操作与下次启动开关
            VStack(spacing: Theme.Spacing.md) {
                Button(action: {
                    hasShownWelcomeSheet = true
                    dismiss()
                }) {
                    Text("开始使用")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                
                Toggle("下次启动不再自动显示", isOn: $hasShownWelcomeSheet)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .frame(width: 480)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
}

// MARK: - 苹果经典特性行 (Feature Row)
private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .alignmentGuide(.top) { d in d[.top] + 2 }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .default).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }
}

#if canImport(PreviewsMacros)
#Preview {
    WelcomeView()
}
#endif
