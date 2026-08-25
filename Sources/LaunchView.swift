import SwiftUI

// MARK: - PDF 导入待机空状态 (Launch & Empty State)

/// 遵循 Apple HIG 规范的未打开文档待机主页，支持按钮选择与整页拖放单个 PDF，包含核心能力摘要。
struct LaunchView: View {
    let errorMessage: String?
    let onFileSelected: (URL) -> Void
    let onInvalidFile: (String) -> Void

    @AppStorage("launchDragOver") private var isDragOver = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // 核心待机引导视图
            ContentUnavailableView {
                Label(
                    isDragOver ? "松开以导入 PDF" : "拖放 PDF 文件到此处",
                    systemImage: isDragOver ? "doc.badge.plus" : "doc.text.magnifyingglass"
                )
            } description: {
                Text("支持电子版、扫描件、打印附带水印的各类 PDF 文档")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } actions: {
                Button(action: openFileAction) {
                    Label("选择 PDF 文件...", systemImage: "folder")
                        .font(.headline)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
                .help("从访达选择 PDF 文档 (⌘O)")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.top, Theme.Spacing.xs)
            }

            Spacer()

            // 底部 3 个轻量能力摘要卡片 (Feature Summary Cards)
            HStack(spacing: Theme.Spacing.lg) {
                LaunchFeatureCard(
                    icon: "bolt.horizontal.fill",
                    tint: .orange,
                    title: "智能通道识别",
                    subtitle: "自动匹配电子文本层提取或高精度 Vision OCR"
                )

                LaunchFeatureCard(
                    icon: "wand.and.stars",
                    tint: .blue,
                    title: "灰度滤镜去水印",
                    subtitle: "色阶自动拉伸，智能抹平浅色杂印与彩色印章"
                )

                LaunchFeatureCard(
                    icon: "cpu.fill",
                    tint: .indigo,
                    title: "本地 AI 排版",
                    subtitle: "修复错别字与断句，一键导出纯净 Markdown"
                )
            }
            .frame(maxWidth: 720)
            .padding(.bottom, Theme.Spacing.xl)
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
            isDragOver = false
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
        .accessibilityLabel("PDF 文件待机导入页")
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

// MARK: - 待机页轻量能力卡片
private struct LaunchFeatureCard: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(.caption, design: .default).weight(.bold))
                    .foregroundStyle(.primary)
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
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
