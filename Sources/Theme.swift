import SwiftUI

// MARK: - 全局设计系统主题
struct Theme {
    /// 26 系系统流行的 Liquid Glass (液态玻璃) 视觉风格调色板
    struct ColorPalette {
        /// 还原 Apple 原生液态玻璃质感的多色流体渐变背景
        static let liquidBackground = LinearGradient(
            colors: [
                Color(red: 0.90, green: 0.88, blue: 0.95), // 左上：淡粉紫
                Color(red: 0.72, green: 0.76, blue: 0.85), // 中间：浅天蓝灰
                Color(red: 0.32, green: 0.30, blue: 0.50)  // 右下：深蓝紫
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        /// 玻璃边缘折射反光高光 (模拟厚玻璃边缘的物理受光面)
        static let glassBorderSpecular = Color.white.opacity(0.45)
        
        /// 玻璃暗部阴影描边 (提供边缘折射深度)
        static let glassBorderShadow = Color.black.opacity(0.12)
        
        /// 毛玻璃卡片的基础叠层填充色
        static let glassCardFill = Color.white.opacity(0.15)
    }

    /// 间距规范系统，符合苹果人机交互指南 (HIG) 的 4 或 8 像素递增标准。
    /// 可以有效统一应用内部各个控件的内边距和外边距，避免硬编码乱象。
    struct Spacing {
        /// 极小间距 = 4
        static let xs: CGFloat = 4
        /// 较小间距 = 8
        static let sm: CGFloat = 8
        /// 中等间距 = 12
        static let md: CGFloat = 12
        /// 标准间距 = 16
        static let lg: CGFloat = 16
        /// 较大间距 = 24
        static let xl: CGFloat = 24
        /// 巨大间距 = 40
        static let xxl: CGFloat = 40
        /// 超大间距 = 60
        static let xxxl: CGFloat = 60
    }
}
