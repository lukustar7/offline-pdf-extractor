import SwiftUI
import PDFKit

// MARK: - PDFKit 原生预览包装组件 (遵循 Apple Preview.app 纵向连续顺滑阅读体验)

struct PDFPreviewView: NSViewRepresentable {
    let pdfDocument: PDFDocument?
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        // 恢复为 Apple 原生纵向连续滚动阅读体验
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displayBox = .mediaBox
        pdfView.backgroundColor = .clear

        // 监听系统 PDFView 页面滚动改变通知
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handlePageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // 监听外部缩放控制通知
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleZoomIn(_:)),
            name: NSNotification.Name("PDFZoomIn"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleZoomOut(_:)),
            name: NSNotification.Name("PDFZoomOut"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleZoomFit(_:)),
            name: NSNotification.Name("PDFZoomFit"),
            object: nil
        )

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.parent = self

        if nsView.document !== pdfDocument {
            nsView.document = pdfDocument
        }

        guard let doc = nsView.document, doc.pageCount > 0 else { return }
        let safePageIndex = max(1, min(currentPage, doc.pageCount))

        if let currentVisiblePage = nsView.currentPage {
            let actualPageIndex = doc.index(for: currentVisiblePage) + 1
            if actualPageIndex != safePageIndex {
                if let targetPage = doc.page(at: safePageIndex - 1) {
                    context.coordinator.isUpdatingFromParent = true
                    nsView.go(to: targetPage)
                    context.coordinator.isUpdatingFromParent = false
                }
            }
        } else {
            if let targetPage = doc.page(at: safePageIndex - 1) {
                context.coordinator.isUpdatingFromParent = true
                nsView.go(to: targetPage)
                context.coordinator.isUpdatingFromParent = false
            }
        }
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    // MARK: - Coordinator 控制器
    class Coordinator: NSObject {
        var parent: PDFPreviewView
        weak var pdfView: PDFView?
        var isUpdatingFromParent = false

        init(_ parent: PDFPreviewView) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @MainActor
        @objc func handlePageChanged(_ notification: Notification) {
            guard !isUpdatingFromParent else { return }
            guard let pdfView = notification.object as? PDFView,
                  let doc = pdfView.document,
                  let visiblePage = pdfView.currentPage else { return }

            let pageIndex = doc.index(for: visiblePage) + 1
            if parent.currentPage != pageIndex {
                if pageIndex >= 1 && pageIndex <= doc.pageCount {
                    parent.currentPage = pageIndex
                }
            }
        }

        @MainActor
        @objc func handleZoomIn(_ notification: Notification) {
            pdfView?.zoomIn(nil)
        }

        @MainActor
        @objc func handleZoomOut(_ notification: Notification) {
            pdfView?.zoomOut(nil)
        }

        @MainActor
        @objc func handleZoomFit(_ notification: Notification) {
            pdfView?.autoScales = true
        }
    }
}

#if canImport(PreviewsMacros)
#Preview {
    PDFPreviewView(
        pdfDocument: nil,
        currentPage: .constant(1)
    )
    .frame(width: 700, height: 560)
}
#endif
