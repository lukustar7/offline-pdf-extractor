import SwiftUI

// MARK: - PDF 导入空状态

/// 应用启动后的原生空状态，支持按钮选择与整页拖放单个 PDF。
struct LaunchView: View {
    let errorMessage: String?
    let onFileSelected: (URL) -> Void
    let onInvalidFile: (String) -> Void

    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ContentUnavailableView {
                Label(
                    isDragOver ? "松开以导入 PDF" : "未选择 PDF",
                    systemImage: isDragOver ? "doc.badge.plus" : "doc.text.magnifyingglass"
                )
            } description: {
                Text("选择一个 PDF 文件开始提取文字。")
            } actions: {
                Button(action: openFileAction) {
                    Label("选择 PDF", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
        .background(
            isDragOver
                ? Color.accentColor.opacity(0.08)
                : Color(nsColor: .windowBackgroundColor)
        )
        .animation(.easeInOut(duration: 0.15), value: isDragOver)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            guard url.pathExtension.lowercased() == "pdf" else {
                onInvalidFile("仅支持导入 PDF 格式的文件。")
                return false
            }
            onFileSelected(url)
            return true
        } isTargeted: { targeted in
            isDragOver = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("PDF 文件导入")
    }

    /// 打开 macOS 原生文件选择面板，并将选择结果交给统一加载入口。
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

#if canImport(PreviewsMacros)
#Preview {
    LaunchView(
        errorMessage: nil,
        onFileSelected: { _ in },
        onInvalidFile: { _ in }
    )
    .frame(width: 900, height: 620)
}
#endif
