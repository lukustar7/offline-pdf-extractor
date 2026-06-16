import SwiftUI

// MARK: - 导出路径辅助信息栏组件 (Accessory Bar)
struct AccessoryBarView: View {
    /// 辅助栏最左侧展示的系统图标名称
    let iconName: String
    
    /// 辅助栏的标题前缀文本 (如 "提取成功！导出路径：")
    let title: String
    
    /// 辅助栏的主题高亮色 (如常规提取用系统的 accentColor，AI 净化用 purple)
    let themeColor: Color
    
    /// 导出的 TXT 文本物理文件路径
    let txtFileURL: URL
    
    /// 导出的 Markdown 物理文件路径
    let mdFileURL: URL
    
    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // 最左侧图标
            Image(systemName: iconName)
                .foregroundColor(themeColor)
            
            // 标题前缀
            Text(title)
                .foregroundColor(.secondary)
            
            // TXT 文件链接按钮
            Button(action: {
                // 在 Finder 中选中并激活该文件
                NSWorkspace.shared.activateFileViewerSelecting([txtFileURL])
            }) {
                Text(txtFileURL.lastPathComponent)
                    .underline()
            }
            .buttonStyle(.link)
            .foregroundColor(themeColor)
            
            // 连接词
            Text("和")
                .foregroundColor(.secondary)
            
            // Markdown 文件链接按钮
            Button(action: {
                // 在 Finder 中选中并激活该文件
                NSWorkspace.shared.activateFileViewerSelecting([mdFileURL])
            }) {
                Text(mdFileURL.lastPathComponent)
                    .underline()
            }
            .buttonStyle(.link)
            .foregroundColor(themeColor)
            
            Spacer()
        }
        .font(.system(size: 11))
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.lg)
        // 使用半透明控制背景色，更好地融入 macOS 系统的深浅色外观
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
    }
}
