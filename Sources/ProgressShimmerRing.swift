import SwiftUI

// MARK: - 包含流光质感的圆形进度条 (带 ETA 预计剩余时间)
struct ProgressShimmerRing: View {
    let progress: Double
    let etaText: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                // 背景圆环
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 10)
                
                // 进度条（带渐变，改用系统主强调色与蓝色的渐变，将紫色留给 AI 净化部分）
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                    .stroke(
                        LinearGradient(colors: [.accentColor, .blue, .accentColor], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: -90))
                    .animation(.linear(duration: 0.2), value: progress)
                
                // 进度百分比文本
                VStack(spacing: Theme.Spacing.xs) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                    Text("提取进度")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            
            // ETA 预计剩余时间文本回显，使用系统主色调
            if !etaText.isEmpty {
                Text(etaText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.accentColor)
                    .transition(.opacity)
            }
        }
    }
}
