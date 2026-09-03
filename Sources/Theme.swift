import SwiftUI

// MARK: - 全局设计系统主题 (遵循 Apple Human Interface Guidelines 规范)

struct Theme {
    /// 间距规范系统，符合苹果人机交互指南 (HIG) 的 4/8 像素递增标准。
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 40
        static let xxxl: CGFloat = 60
    }

    /// 圆角规范 (Apple 原生连续圆角体系)
    struct Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    /// 尺度规范 (符合 macOS 原生人体工学尺寸)
    struct Metric {
        static let buttonHeightPrimary: CGFloat = 32
        static let buttonHeightSecondary: CGFloat = 28
        static let cardMinHeight: CGFloat = 48
        static let hudHeight: CGFloat = 36
        static let inputHeight: CGFloat = 28
    }

    /// 光影与层次系统 (符合 macOS 原生物理质感，摒弃无谓的人工蓝光光晕)
    struct Shadow {
        /// 物理纸张自然漫反射阴影 (双层复合环境光模拟)
        static func paper<V: View>(_ view: V) -> some View {
            view
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
        }

        /// 悬浮面板与 HUD 轻投影
        static func floatingGlass<V: View>(_ view: V) -> some View {
            view
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        }

        /// 容器卡片微阴影
        static func card<V: View>(_ view: V) -> some View {
            view
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        }
    }
}

// MARK: - 原生修饰符扩展

extension View {
    /// 物理纸张立体阴影
    func paperShadow() -> some View {
        Theme.Shadow.paper(self)
    }

    /// 悬浮面板微阴影
    func floatingGlassShadow() -> some View {
        Theme.Shadow.floatingGlass(self)
    }

    /// 卡片微阴影
    func bentoCardShadow() -> some View {
        Theme.Shadow.card(self)
    }

    /// 原生极细微描边 (系统语义分隔线自适应)
    func liquidGlassBorder(cornerRadius: CGFloat = Theme.Radius.md, isSelected: Bool = false) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.35),
                    lineWidth: isSelected ? 1.5 : 0.6
                )
        )
    }

    /// 极细微描边别名
    func subtleBorder(cornerRadius: CGFloat = Theme.Radius.md, isSelected: Bool = false) -> some View {
        liquidGlassBorder(cornerRadius: cornerRadius, isSelected: isSelected)
    }

    /// 胶囊语义描边
    func liquidGlassPillBorder(isSelected: Bool = false) -> some View {
        self.overlay(
            Capsule(style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.35),
                    lineWidth: isSelected ? 1.2 : 0.5
                )
        )
    }

    /// 晶莹半透明容器底色
    func liquidGlassBackground(cornerRadius: CGFloat = Theme.Radius.md, opacity: Double = 0.75) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
