import SwiftUI

// MARK: - 极简全屏启动导入视图
/// 打开应用时提示用户拖入或选择文件，只支持单文件处理。
struct LaunchView: View {
    /// 触发加载文件动作的回调
    var onFileSelected: (URL) -> Void
    var onInvalidFile: (String) -> Void
    
    // 是否有文件正在拖过导入区
    @State private var isDragOver = false
    
    // 鼠标悬停时只改变描边和底色，避免大幅缩放造成窗口内元素晃动。
    @State private var isHovered = false
    
    var body: some View {
        VStack {
            Spacer(minLength: Theme.Spacing.xxl)
            
            Button(action: openFileAction) {
                VStack(spacing: Theme.Spacing.lg) {
                    Image(systemName: isDragOver ? "doc.badge.plus" : "doc.text.magnifyingglass")
                        .font(.system(size: 42, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isDragOver ? Color.accentColor : .secondary)
                    
                    VStack(spacing: Theme.Spacing.xs) {
                        Text(isDragOver ? "松开以导入 PDF" : "导入 PDF")
                            .font(.system(.title3, design: .default).weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        Text("拖入文件，或点击此区域选择 PDF。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Text("支持电子文本、扫描正文加电子水印、全扫描件三类处理场景。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.vertical, Theme.Spacing.xxl)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isDragOver || isHovered ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.8), lineWidth: isDragOver ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 560)
            .padding(.horizontal, Theme.Spacing.xxl)
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
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            
            Spacer(minLength: Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
