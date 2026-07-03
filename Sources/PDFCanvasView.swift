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
            Image(systemName: scenarioSymbolName)
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
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .cornerRadius(8)
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
    
    private var scenarioSymbolName: String {
        switch processingScenario {
        case .electronicTextWithTextWatermark:
            return "doc.text"
        case .scannedTextWithTextWatermark:
            return "doc.viewfinder"
        case .fullyScanned:
            return "scanner"
        }
    }
}
