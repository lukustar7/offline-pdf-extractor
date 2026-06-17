import SwiftUI

// MARK: - SettingCardToggleStyle 原生卡片 ToggleStyle
/// 100% 遵循 Apple HIG 的原生卡片样式选择器风格。
/// 废除用普通 HStack + onTapGesture 臆造单选的做法，保留系统的 Plain 按钮底层焦点环、键盘导航 Tab 支持与无障碍语义。
struct SettingCardToggleStyle: ToggleStyle {
    let title: String
    let subTitle: String
    let themeColor: Color
    
    // 鼠标悬停状态，用于触发 macOS 最新 26 系系统的“气垫式”悬浮弹性动效
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            // 点击时切换状态
            configuration.isOn = true
        }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
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
            .cornerRadius(12)
            // 物理厚玻璃双重边缘描边工艺
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        configuration.isOn ? themeColor : Color(nsColor: .separatorColor).opacity(0.6),
                        lineWidth: configuration.isOn ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain) // 关键：PlainStyle 能让 macOS 键盘焦点在 Tab 切换时完美框住整个卡片
        // 挂载气垫式 Hover 微动效
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.05 : 0.0), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 包装层：单选方块卡片组件
struct SettingSelectorCard: View {
    let title: String
    let subTitle: String
    let isSelected: Bool
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
        .toggleStyle(SettingCardToggleStyle(title: title, subTitle: subTitle, themeColor: themeColor))
    }
}
