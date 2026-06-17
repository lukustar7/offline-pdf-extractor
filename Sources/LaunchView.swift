import SwiftUI

// MARK: - 极简全屏启动导入视图
/// 打开应用时全屏提示用户拖入或选择文件，只支持单文件处理，采用奢华的 Liquid Glass (液态玻璃) 视觉风格。
struct LaunchView: View {
    /// 触发加载文件动作的回调
    var onFileSelected: (URL) -> Void
    var onInvalidFile: (String) -> Void
    
    // 是否有文件正在拖过导入区
    @State private var isDragOver = false
    
    // 鼠标悬停形变响应
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            // 背景层：全屏液态流体渐变
            Theme.ColorPalette.liquidBackground
                .ignoresSafeArea()
            
            // 核心卡片容器：毛玻璃材质 + 双层物理反光描边
            VStack(spacing: Theme.Spacing.xl) {
                
                // 拟物化液态玻璃水滴图标底座 (标准提取蓝色)
                LiquidGlassIconBase(iconName: "doc.badge.plus", usePurpleTheme: false)
                    .scaleEffect(isDragOver ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isDragOver)
                
                // 大字操作提示语
                VStack(spacing: Theme.Spacing.sm) {
                    Text(isDragOver ? "松开鼠标导入文件" : "拖入 PDF 文件至此区域")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundColor(.primary)
                    
                    Text("或者点击此处浏览并导入")
                        .font(.system(.body))
                        .foregroundColor(.secondary)
                }
                
                // 小字说明规范，符合苹果 transparent UI 理念
                Text("⚠️ 注意：本工具仅支持单文件文字提取与水印过滤，且 100% 运行于本地沙盒中，保障数据绝对私密。")
                    .font(.system(.caption2))
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
            .frame(width: 480, height: 320)
            // 声明式超薄毛玻璃底材
            .background(.ultraThinMaterial)
            .cornerRadius(28)
            // 模拟高折射率物理玻璃边缘
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Theme.ColorPalette.glassBorderSpecular, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Theme.ColorPalette.glassBorderShadow, lineWidth: 1.5)
                        .padding(0.5)
                }
            )
            // 鼠标悬停时的气垫微放大和投影
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(
                color: Color.black.opacity(isHovered ? 0.16 : 0.1),
                radius: isHovered ? 30 : 20,
                x: 0,
                y: isHovered ? 15 : 10
            )
            .contentShape(Rectangle())
            // 点击拉起系统选择面板
            .onTapGesture {
                openFileAction()
            }
            // 接收 PDF 物理文件拖放
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        if url.pathExtension.lowercased() == "pdf" {
                            DispatchQueue.main.async {
                                onFileSelected(url)
                            }
                        } else {
                            DispatchQueue.main.async {
                                onInvalidFile("仅支持导入 PDF 格式的文件。")
                            }
                        }
                    }
                }
                return true
            }
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    isHovered = hovering
                }
            }
        }
        // 无障碍适配
        .accessibilityElement(children: .combine)
        .accessibilityLabel("全屏 PDF 导入启动区")
        .accessibilityHint("将需要提取正文的 PDF 文件拖拽到此，或点击该区域浏览选择 PDF 文件导入。仅支持单文件。")
    }
    
    /// 触发 macOS 系统的选择文件面板
    private func openFileAction() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            onFileSelected(url)
        }
    }
}
