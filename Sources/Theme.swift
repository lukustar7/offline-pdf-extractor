import SwiftUI

// MARK: - 全局设计系统主题 (Apple HIG 物理纸张与材质规范)
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
    
    /// 圆角规范
    struct Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let pill: CGFloat = 999
    }
    
    /// 光影与层次系统
    struct Shadow {
        /// 物理纸张立体环境光阴影 (双层复合模拟)
        static func paper<V: View>(_ view: V) -> some View {
            view
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        }
        
        /// 悬浮胶囊/HUD 阴影
        static func floating<V: View>(_ view: V) -> some View {
            view
                .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 4)
        }
        
        /// 轻量卡片微阴影
        static func card<V: View>(_ view: V) -> some View {
            view
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - 常用视图修饰扩展
extension View {
    /// 物理纸张立体阴影
    func paperShadow() -> some View {
        Theme.Shadow.paper(self)
    }
    
    /// 悬浮 HUD 阴影
    func floatingHUDShadow() -> some View {
        Theme.Shadow.floating(self)
    }
    
    /// 极细系统级物理描边
    func subtleBorder(cornerRadius: CGFloat = Theme.Radius.md) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
        )
    }
}
