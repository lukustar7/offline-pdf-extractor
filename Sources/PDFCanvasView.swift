import SwiftUI
@preconcurrency import PDFKit

// MARK: - PDF 主工作画布 (Apple 原生物理纸张与沉浸式交互)

/// 具备物理纸张悬浮立体感、视口缩放控制、去水印对比视口与扫描微光动效的主画布。
struct PDFCanvasView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @Binding var currentPage: Int
    
    @AppStorage("processingScenario") private var processingScenario: PDFProcessingScenario = .electronicTextWithTextWatermark
    @AppStorage("removeLightWatermarks") private var removeLightWatermarks = true
    @AppStorage("removeColorStamps") private var removeColorStamps = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部精致文档状态栏
            canvasHeader
            
            Divider()
            
            // 主视口与悬浮控制
            ZStack(alignment: .topTrailing) {
                // PDF 页面画布展示区
                mainViewport
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 右上角浮动视口控制胶囊
                floatingViewportControls
                    .padding(Theme.Spacing.md)
                
                // 处理中 HUD 浮动胶囊
                if engine.isProcessing {
                    processingHUD
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, Theme.Spacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
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
                    Text("原始扫描件 (含水印)")
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
                    Text("Core Image 滤镜处理后 (OCR 识别源)")
                        .font(.caption)
                        .foregroundStyle(.tint)
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
            // 标准 PDF 交互阅读视口
            ZStack {
                PDFPreviewView(
                    pdfDocument: engine.pdfDocument,
                    currentPage: $currentPage
                )
                .padding(Theme.Spacing.md)
                
                // 扫描中微光扫描动效 (Scanning Light Shimmer)
                if engine.isProcessing {
                    scanningLightOverlay
                }
            }
        }
    }
    
    // MARK: - 顶部精致文档状态栏
    private var canvasHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: processingScenario.systemImage)
                .font(.system(.body).weight(.semibold))
                .foregroundStyle(scenarioTintColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(engine.pdfFileName.isEmpty ? "未加载文档" : engine.pdfFileName)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .lineLimit(1)
                
                if engine.pdfTotalPages > 0 {
                    Text("\(processingScenario.title) · 第 \(currentPage) / \(engine.pdfTotalPages) 页 · \(engine.pdfFileSize)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // 扫描件场景下的去水印对比开关
            if processingScenario != .electronicTextWithTextWatermark && engine.pdfDocument != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        engine.isComparisonMode.toggle()
                        if engine.isComparisonMode {
                            engine.updateComparisonPreview(
                                removeLightWatermarks: removeLightWatermarks,
                                removeColorStamps: removeColorStamps
                            )
                        }
                    }
                } label: {
                    Label(
                        engine.isComparisonMode ? "退出对比" : "对比去水印效果",
                        systemImage: engine.isComparisonMode ? "eye.slash.fill" : "eye.fill"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("查看 Core Image 色阶去水印前后的图像净化对比效果")
            }
            
            statusPill
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
    }
    
    private var statusPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .clipShape(Capsule())
    }
    
    // MARK: - 右上角浮动视口控制胶囊
    private var floatingViewportControls: some View {
        HStack(spacing: 2) {
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("PDFZoomIn"), object: nil)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("放大页面")
            
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("PDFZoomOut"), object: nil)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("缩小页面")
            
            Divider()
                .frame(height: 12)
            
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("PDFZoomFit"), object: nil)
            } label: {
                Text("适合窗口")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .help("自适应缩放至当前窗口大小")
        }
        .padding(2)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .clipShape(Capsule())
        .floatingHUDShadow()
        .subtleBorder(cornerRadius: Theme.Radius.pill)
    }
    
    // MARK: - 扫描中微光扫描动效
    private var scanningLightOverlay: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.0),
                            Color.accentColor.opacity(0.25),
                            Color.accentColor.opacity(0.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 40)
                .offset(y: engine.isScanningAnimating ? geo.size.height - 40 : 0)
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
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    // MARK: - 处理进度 HUD 浮动胶囊
    private var processingHUD: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                
                Text(engine.currentStatus)
                    .font(.caption)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if !engine.etaString.isEmpty {
                    Text(engine.etaString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            ProgressView(value: engine.progress)
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
        .frame(maxWidth: 380)
        .padding(Theme.Spacing.md)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .floatingHUDShadow()
        .subtleBorder(cornerRadius: Theme.Radius.md)
    }
    
    private var statusText: String {
        if engine.isAnalyzingWatermarks { return "分析水印中" }
        if engine.isProcessing { return "文字提取中" }
        if engine.extractedPagesText.isEmpty { return "就绪" }
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
