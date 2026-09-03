import SwiftUI
@preconcurrency import PDFKit

// MARK: - 左侧页面缩略图导航栏 (Apple HIG Preview/Keynote 风格)

/// 纯正原生的大纲与页面缩略图导航，支持非阻塞式异步生成与实时跳转。
struct SidebarThumbnailView: View {
    @ObservedObject var engine: PDFExtractorEngine

    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏标题与统计
            sidebarHeader

            Divider()

            // 页面缩略图纵向滚动流
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(1...max(1, engine.pdfTotalPages), id: \.self) { pageNumber in
                            ThumbnailRowItem(
                                pageNumber: pageNumber,
                                isSelected: engine.currentPage == pageNumber,
                                thumbnailImage: engine.thumbnails[pageNumber],
                                status: pageStatus(for: pageNumber),
                                onSelect: {
                                    engine.currentPage = pageNumber
                                    engine.preloadThumbnailsAround(pageNumber: pageNumber)
                                }
                            )
                            .id(pageNumber)
                            .onAppear {
                                engine.loadThumbnail(for: pageNumber)
                            }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.sm)
                }
                .onChange(of: engine.currentPage) { oldValue, newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private var sidebarHeader: some View {
        HStack {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("缩略图")
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text("共 \(engine.pdfTotalPages) 页")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .clipShape(Capsule())
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func pageStatus(for page: Int) -> ThumbnailPageStatus {
        if engine.isProcessing && engine.currentPage == page {
            return .processing
        }
        if engine.extractedPagesText[page] != nil {
            return .extracted
        }
        return .idle
    }
}

// MARK: - 页面提取状态
enum ThumbnailPageStatus {
    case idle
    case processing
    case extracted
}

// MARK: - 单个缩略图卡片
private struct ThumbnailRowItem: View {
    let pageNumber: Int
    let isSelected: Bool
    let thumbnailImage: NSImage?
    let status: ThumbnailPageStatus
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Theme.Spacing.xs) {
                // 缩略图容器与物理纸张立体投影
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = thumbnailImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Rectangle()
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.7)
                                )
                        }
                    }
                    .frame(width: 120, height: 160)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: isSelected ? 2.5 : 0.5)
                    )
                    .shadow(color: Color.black.opacity(isSelected ? 0.2 : 0.08), radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 3 : 2)

                    // 状态角标
                    statusBadge
                        .padding(4)
                }

                // 页码文字标签
                Text("\(pageNumber)")
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
            }
            .padding(Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .processing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.5)
                .padding(2)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
        case .extracted:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .background(Circle().fill(Color.white))
        case .idle:
            EmptyView()
        }
    }
}

#if canImport(PreviewsMacros)
#Preview {
    SidebarThumbnailView(engine: PDFExtractorEngine())
        .frame(width: 180, height: 600)
}
#endif
