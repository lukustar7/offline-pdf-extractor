import SwiftUI

// MARK: - 全局设计系统主题
struct Theme {
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
