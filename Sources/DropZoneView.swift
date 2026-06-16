import SwiftUI

// MARK: - 拖拽导入虚线框视图
struct DropZoneView: View {
    @Binding var isDragOver: Bool
    var onFileDropped: (URL) -> Void
    var onInvalidFileDropped: (() -> Void)? = nil // 拖入非 PDF 时的错误回调 (P1-5 修复)
    
    // 适配最新 macOS 设计语言：卡片悬停气垫弹簧形变状态
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(isDragOver ? .accentColor : .secondary)
                .scaleEffect(isDragOver ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragOver)
            
            VStack(spacing: Theme.Spacing.xs) {
                Text("拖入 PDF 文件到此区域")
                    .font(.system(size: 13, weight: .semibold))
                Text("或者点击浏览文件")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDragOver ? Color.accentColor : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 10, dash: [6, 4], dashPhase: 0))
                .background(isDragOver ? Color.accentColor.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.pdf]
            if panel.runModal() == .OK, let url = panel.url {
                onFileDropped(url)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url = url {
                    if url.pathExtension.lowercased() == "pdf" {
                        DispatchQueue.main.async {
                            onFileDropped(url)
                        }
                    } else {
                        DispatchQueue.main.async {
                            // 拖入非 PDF 格式文件时，执行失败反馈 (P1-5 修复)
                            onInvalidFileDropped?()
                        }
                    }
                }
            }
            return true
        }
        // 添加基本的无障碍朗读支持 (P3-7 修复)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PDF 拖放导入区域")
        .accessibilityHint("将 PDF 格式的文件拖拽到此区域，或点击此区域浏览并导入文件")
        // macOS 最新设计语言：鼠标悬停产生气垫弹性放大与投影反馈，手感极佳
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.06 : 0.0), radius: 10, x: 0, y: 5)
    }
}
