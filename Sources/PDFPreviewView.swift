import SwiftUI
import PDFKit

// MARK: - PDFKit 原生预览包装组件
struct PDFPreviewView: NSViewRepresentable {
    let pdfDocument: PDFDocument?
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayBox = .mediaBox
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        // 只有在 document 不一致时更新，防止重复设置重置滚动位置
        if nsView.document !== pdfDocument {
            nsView.document = pdfDocument
        }
    }
}
