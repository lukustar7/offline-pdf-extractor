import SwiftUI
@preconcurrency import PDFKit

// MARK: - PDF 主工作画布 (遵循 Apple 纯净文档视口规范)

/// 具备高保真物理纸张质感、纵向连续顺滑滚动与去水印对比能力的主视口画布。
struct PDFCanvasView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @Binding var currentPage: Int

    @AppStorage("processingScenario") private var processingScenario: PDFProcessingScenario = .electronicTextWithTextWatermark
    @AppStorage("removeLightWatermarks") private var removeLightWatermarks = true
    @AppStorage("removeColorStamps") private var removeColorStamps = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // PDF 主阅读视口或去水印前后对比视口
            mainViewport
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 提取中浮动进度 HUD
            if engine.isProcessing {
                processingHUD
                    .padding(.bottom, Theme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - 主视口与对比展示
    @ViewBuilder
    private var mainViewport: some View {
        if engine.isComparisonMode,
           let original = engine.comparisonOriginal,
           let filtered = engine.comparisonFiltered {
            // 去水印前后对比视口 (Before / After Split)
            HStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("原始扫描件 (含印章/水印)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(nsImage: original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(Color.white)
                        .paperShadow()
                        .subtleBorder()
                }

                VStack(spacing: Theme.Spacing.xs) {
                    Text("Core Image 通道过滤后 (OCR 识别源)")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Image(nsImage: filtered)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(Color.white)
                        .paperShadow()
                        .subtleBorder()
                }
            }
            .padding(Theme.Spacing.xl)
            .transition(.opacity)
        } else {
            // 标准 PDF 连续滚动阅读视口
            ZStack {
                PDFPreviewView(
                    pdfDocument: engine.pdfDocument,
                    currentPage: $currentPage
                )

                // 处理中微光动画
                if engine.isProcessing {
                    scanningLightOverlay
                }
            }
        }
    }

    // MARK: - 扫描中微光扫描动效
    private var scanningLightOverlay: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.0),
                            Color.accentColor.opacity(0.18),
                            Color.accentColor.opacity(0.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 36)
                .offset(y: engine.isScanningAnimating ? geo.size.height - 36 : 0)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.6)
                        .repeatForever(autoreverses: true)
                    ) {
                        engine.isScanningAnimating = true
                    }
                }
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    // MARK: - 处理进度 HUD 浮动面板 (遵循 Apple 原生 HUD 规范)
    private var processingHUD: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)

                Text(engine.currentStatus)
                    .font(.callout)
                    .foregroundStyle(.primary)

                Spacer()

                if !engine.etaString.isEmpty {
                    Text(engine.etaString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: engine.progress)
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
        .frame(maxWidth: 360)
        .padding(Theme.Spacing.md)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .subtleBorder(cornerRadius: Theme.Radius.lg)
        .floatingGlassShadow()
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
