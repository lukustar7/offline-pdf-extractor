import SwiftUI

// MARK: - 全局设计系统主题 (Apple HIG & Liquid Glass 液态流光玻璃规范)

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
    
    /// 圆角规范 (Liquid Glass 现代圆润几何体系)
    struct Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22
        static let pill: CGFloat = 999
    }
    
    /// 尺度规范 (拒绝小家子气，全面采用 36px~40px 现代大气尺寸)
    struct Metric {
        static let buttonHeightPrimary: CGFloat = 36
        static let buttonHeightSecondary: CGFloat = 32
        static let cardMinHeight: CGFloat = 56
        static let hudHeight: CGFloat = 38
        static let inputHeight: CGFloat = 30
    }
    
    /// 光影与层次系统 (Liquid Glass 3D 纵深与环境光晕)
    struct Shadow {
        /// 物理纸张立体环境光阴影 (双层复合模拟 + 柔和蓝色环境呼吸光晕)
        static func paper<V: View>(_ view: V) -> some View {
            view
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 10)
                .shadow(color: Color.accentColor.opacity(0.12), radius: 36, x: 0, y: 0)
        }
        
        /// 悬浮 Liquid Glass HUD 阴影 (轻盈浮动感)
        static func floatingGlass<V: View>(_ view: V) -> some View {
            view
                .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 6)
                .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
        
        /// Bento 卡片微浮动阴影
        static func card<V: View>(_ view: V) -> some View {
            view
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }
}

// MARK: - Liquid Glass 原生修饰符扩展

extension View {
    /// 物理纸张立体光晕阴影
    func paperShadow() -> some View {
        Theme.Shadow.paper(self)
    }
    
    /// 悬浮 Liquid Glass HUD 阴影
    func floatingGlassShadow() -> some View {
        Theme.Shadow.floatingGlass(self)
    }
    
    /// Bento 卡片微阴影
    func bentoCardShadow() -> some View {
        Theme.Shadow.card(self)
    }
    
    /// Liquid Glass 极细流光边缘描边 (物理折射高光)
    func liquidGlassBorder(cornerRadius: CGFloat = Theme.Radius.md, isSelected: Bool = false) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isSelected
                        ? LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color(nsColor: .separatorColor).opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                    lineWidth: isSelected ? 1.5 : 0.6
                )
        )
    }
    
    /// 兼容性别名：极细流光描边
    func subtleBorder(cornerRadius: CGFloat = Theme.Radius.md) -> some View {
        liquidGlassBorder(cornerRadius: cornerRadius)
    }
    
    /// Liquid Glass 胶囊流光描边
    func liquidGlassPillBorder(isSelected: Bool = false) -> some View {
        self.overlay(
            Capsule(style: .continuous)
                .stroke(
                    isSelected
                        ? LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color(nsColor: .separatorColor).opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                    lineWidth: isSelected ? 1.2 : 0.5
                )
        )
    }
    
    /// Liquid Glass 晶莹毛玻璃容器底色
    func liquidGlassBackground(cornerRadius: CGFloat = Theme.Radius.md, opacity: Double = 0.75) -> some View {
        self
            .background(
                ZStack {
                    VisualEffectView(material: .popover, blendingMode: .withinWindow)
                    Color(nsColor: .controlBackgroundColor).opacity(opacity)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
