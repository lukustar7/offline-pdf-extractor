import SwiftUI

// MARK: - Liquid Glass (液态玻璃) 卡片容器组件
/// 实现 26 系系统中最前沿的液态玻璃风格，包含多色流体渐变、超大圆角、毛玻璃混合以及厚玻璃边缘双层折射描边。
struct LiquidGlassContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // 底层：流体渐变背景，还原图片中柔和且高雅的粉紫-天蓝-深紫过渡
            Theme.ColorPalette.liquidBackground
                .ignoresSafeArea()
            
            // 中层：高折射率玻璃卡片本体
            VStack {
                content
            }
            // 采用超大圆角，配合超薄材质 (.ultraThinMaterial) 营造纯净的透光质感
            .padding(Theme.Spacing.xxl)
            .background(.ultraThinMaterial)
            .cornerRadius(28)
            // 核心工艺：通过双层微调描边 (Stroke) 模拟玻璃厚度在受光面和背光面的物理折射边缘
            .overlay(
                ZStack {
                    // 外层：受光面高光白边 (1px)
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Theme.ColorPalette.glassBorderSpecular, lineWidth: 1)
                    
                    // 内层：偏暗的边缘阴影 (1.5px) 提供折射厚度感
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Theme.ColorPalette.glassBorderShadow, lineWidth: 1.5)
                        .padding(0.5)
                }
            )
            // 极低频长半径软阴影，使卡片悬浮在液态渐变背景之上
            .shadow(color: Color.black.opacity(0.12), radius: 40, x: 0, y: 20)
            .padding(Theme.Spacing.xxl)
        }
    }
}

// MARK: - Liquid Glass 拟物化玻璃水滴图标底座
/// 模拟图片中头像部分的凹凸浮雕反射玻璃底座，使用双环渐变和多段投影。
struct LiquidGlassIconBase: View {
    let iconName: String
    var usePurpleTheme: Bool = false
    
    var body: some View {
        ZStack {
            // 底座玻璃圆环 - 外部亮边
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 110, height: 110)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            
            // 底座本体 - 超薄毛玻璃
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 104, height: 104)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.black.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            
            // 内层渐变小圆环，增强水滴般的折射聚光点
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            (usePurpleTheme ? Color.purple : Color.accentColor).opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 86, height: 86)
            
            // 居中的 SF Symbol 图标，微带倒影感
            Image(systemName: iconName)
                .font(.system(size: 38, weight: .thin))
                .foregroundColor(usePurpleTheme ? .purple : .accentColor)
                .shadow(color: (usePurpleTheme ? Color.purple : Color.accentColor).opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }
}
