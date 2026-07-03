import SwiftUI

// MARK: - SettingCardToggleStyle 原生卡片 ToggleStyle
/// 使用 ToggleStyle 封装三类 PDF 场景单选卡，保留系统按钮焦点环、键盘导航与无障碍语义。
struct SettingCardToggleStyle: ToggleStyle {
    let title: String
    let subTitle: String
    let systemImage: String?
    let themeColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            // 点击时切换状态
            configuration.isOn = true
        }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(.callout).weight(.semibold))
                            .foregroundColor(configuration.isOn ? themeColor : .secondary)
                            .frame(width: 18)
                    }
                    // 大字标题
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundColor(configuration.isOn ? themeColor : .primary)
                    Spacer()
                    // 选中状态的小对勾指示器
                    if configuration.isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(themeColor)
                            .font(.system(.subheadline))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                
                // 小字说明说明文案
                Text(subTitle)
                    .font(.system(.caption2))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            // 采用超薄磨砂作为底色，提升层级感
            .background(configuration.isOn ? themeColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .cornerRadius(8)
            // 物理厚玻璃双重边缘描边工艺
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        configuration.isOn ? themeColor : Color(nsColor: .separatorColor).opacity(0.6),
                        lineWidth: configuration.isOn ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain) // PlainStyle 能让 macOS 键盘焦点在 Tab 切换时覆盖整张卡片。
    }
}

// MARK: - 包装层：单选方块卡片组件
struct SettingSelectorCard: View {
    let title: String
    let subTitle: String
    let isSelected: Bool
    var systemImage: String? = nil
    var themeColor: Color = .accentColor
    let action: () -> Void
    
    var body: some View {
        Toggle(isOn: Binding<Bool>(
            get: { isSelected },
            set: { _ in action() }
        )) {
            // 隐藏默认标题
            EmptyView()
        }
        .toggleStyle(SettingCardToggleStyle(title: title, subTitle: subTitle, systemImage: systemImage, themeColor: themeColor))
    }
}
