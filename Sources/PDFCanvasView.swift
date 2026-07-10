import SwiftUI

// MARK: - PDF 主画布
struct PDFCanvasView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @Binding var currentPage: Int
    
    @AppStorage("processingScenario") private var processingScenario: PDFProcessingScenario = .electronicTextWithTextWatermark
    
    var body: some View {
        VStack(spacing: 0) {
            canvasHeader
            
            Divider()
            
            ZStack(alignment: .bottom) {
                PDFPreviewView(
                    pdfDocument: engine.pdfDocument,
                    currentPage: $currentPage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                
                if engine.isProcessing {
                    processingRail
                        .padding(Theme.Spacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }
    
    private var canvasHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: processingScenario.systemImage)
                .font(.system(.title3).weight(.semibold))
                .foregroundStyle(scenarioTintColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.pdfFileName)
                    .font(.system(.headline, design: .default).weight(.semibold))
                    .lineLimit(1)
                Text("\(processingScenario.title) · \(engine.pdfTotalPages) 页 · \(engine.pdfFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            statusPill
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
    }
    
    private var statusPill: some View {
        Label(statusText, systemImage: statusSymbolName)
            .font(.caption)
            .foregroundStyle(statusColor)
            .lineLimit(1)
    }
    
    private var processingRail: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(engine.currentStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(engine.etaString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            ProgressView(value: engine.progress)
                .progressViewStyle(.linear)
        }
        .padding(Theme.Spacing.md)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
    }
    
    private var statusText: String {
        if engine.isAnalyzingWatermarks { return "分析中" }
        if engine.isProcessing { return "提取中" }
        if engine.extractedPagesText.isEmpty { return "待提取" }
        return "已提取"
    }
    
    private var statusColor: Color {
        if engine.isProcessing || engine.isAnalyzingWatermarks { return .orange }
        if engine.extractedPagesText.isEmpty { return .secondary }
        return .green
    }

    private var statusSymbolName: String {
        if engine.isProcessing || engine.isAnalyzingWatermarks { return "clock" }
        if engine.extractedPagesText.isEmpty { return "circle" }
        return "checkmark.circle.fill"
    }
    
    private var scenarioTintColor: Color {
        switch processingScenario {
        case .electronicTextWithTextWatermark:
            return .blue
        case .scannedTextWithTextWatermark:
            return .indigo
        case .fullyScanned:
            return .orange
        }
    }
    
}

#if canImport(PreviewsMacros)
#Preview {
    PDFCanvasView(
        engine: PDFExtractorEngine(),
        currentPage: .constant(1)
    )
    .frame(width: 720, height: 680)
}
#endif
