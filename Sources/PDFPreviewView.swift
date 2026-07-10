import SwiftUI
import PDFKit

// MARK: - PDFKit 原生预览包装组件 (支持双向物理页码绑定)
/// 支持在滚动预览 PDF 原件时同步外层页码，也支持外部翻页时自动跳转至对应物理页。
struct PDFPreviewView: NSViewRepresentable {
    let pdfDocument: PDFDocument?
    @Binding var currentPage: Int
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.displayBox = .mediaBox
        
        // 监听系统 PDFView 页面滚动改变通知
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handlePageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        // 双向重绑定 parent
        context.coordinator.parent = self
        
        // 1. 只有在 document 不一致时更新，防止重复设置重置滚动位置
        if nsView.document !== pdfDocument {
            nsView.document = pdfDocument
        }
        
        // 2. 双向联动：外部翻页指令 -> 控制 PDFView 自动跳转对应页
        guard let doc = nsView.document, doc.pageCount > 0 else { return }
        
        let safePageIndex = max(1, min(currentPage, doc.pageCount))
        
        if let currentVisiblePage = nsView.currentPage {
            let actualPageIndex = doc.index(for: currentVisiblePage) + 1
            if actualPageIndex != safePageIndex {
                if let targetPage = doc.page(at: safePageIndex - 1) {
                    // 跳转前指示 Coordinator 忽略本次由父视图驱动的跳页通知，防止循环触发
                    context.coordinator.isUpdatingFromParent = true
                    nsView.go(to: targetPage)
                    context.coordinator.isUpdatingFromParent = false
                }
            }
        } else {
            // 刚加载文档时，初始化跳转第一页
            if let targetPage = doc.page(at: safePageIndex - 1) {
                context.coordinator.isUpdatingFromParent = true
                nsView.go(to: targetPage)
                context.coordinator.isUpdatingFromParent = false
            }
        }
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewPageChanged,
            object: nsView
        )
    }
    
    // MARK: - Coordinator 控制器，实现防抖与双向通知中介
    class Coordinator: NSObject {
        var parent: PDFPreviewView
        
        /// 标志位：是否正在响应由父视图（例如翻页按钮）触发的页面跳转，用于防止通知环路
        var isUpdatingFromParent = false
        
        init(_ parent: PDFPreviewView) {
            self.parent = parent
        }
        
        @MainActor
        @objc func handlePageChanged(_ notification: Notification) {
            // 如果是外部更新引起的通知，忽略它，不向外回传
            guard !isUpdatingFromParent else { return }
            
            guard let pdfView = notification.object as? PDFView,
                  let doc = pdfView.document,
                  let visiblePage = pdfView.currentPage else { return }
            
            let pageIndex = doc.index(for: visiblePage) + 1
            
            // 安全回传，只在页面发生真实物理移动时回传
            if parent.currentPage != pageIndex {
                let maximumPageCount = doc.pageCount
                // PDFView 页面通知由主线程发出，可直接同步绑定，避免额外排队导致页码闪回。
                if pageIndex >= 1 && pageIndex <= maximumPageCount {
                    parent.currentPage = pageIndex
                }
            }
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
