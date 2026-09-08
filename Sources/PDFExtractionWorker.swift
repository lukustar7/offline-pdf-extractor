import AppKit
import CoreImage
@preconcurrency import PDFKit
@preconcurrency import Vision

// MARK: - PDF 后台传输模型

/// `PDFDocument` 尚未声明 Sendable；该包装只执行一次所有权转移，之后文档仅供主线程 PDFView 使用。
struct PDFDocumentLoadResult: @unchecked Sendable {
    let document: PDFDocument
    let pageCount: Int
    let isLocked: Bool
    let hasTextLayer: Bool
}

struct DetectedWatermark: Sendable {
    let text: String
    let occurrenceCount: Int
}

public struct PageExtractionOutput: Sendable {
    public let content: ExtractedPageContent
    public let warning: String?

    public init(content: ExtractedPageContent, warning: String?) {
        self.content = content
        self.warning = warning
    }
}

private struct OCRLineInfo: Sendable {
    let text: String
    let rect: CGRect
}

private struct OCRExtractionOutput: Sendable {
    let lines: [OCRLineInfo]
    let fullText: String
    let warning: String?
}

// MARK: - PDF 后台加载器

/// 将可能较慢的 PDF 初始化与水印词频统计移出主线程。
enum PDFDocumentLoader {
    static func load(url: URL) async -> PDFDocumentLoadResult? {
        let task = Task.detached(priority: .userInitiated) { () -> PDFDocumentLoadResult? in
            guard let document = PDFDocument(url: url) else { return nil }

            // 智能抽样前 5 页探测是否存在可直接读取的矢量字符层
            var totalSampleChars = 0
            let samplePages = min(document.pageCount, 5)
            for i in 0..<samplePages {
                if let page = document.page(at: i) {
                    totalSampleChars += page.string?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
                }
            }
            let averageChars = samplePages > 0 ? (totalSampleChars / samplePages) : 0
            let hasTextLayer = averageChars >= 25

            return PDFDocumentLoadResult(
                document: document,
                pageCount: document.pageCount,
                isLocked: document.isLocked,
                hasTextLayer: hasTextLayer
            )
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// 最多扫描前 30 页，并限制候选字典为 5,000 项，避免异常 PDF 无限制占用内存。
    static func detectWatermarks(url: URL) async -> [DetectedWatermark] {
        let task = Task.detached(priority: .userInitiated) { () -> [DetectedWatermark] in
            guard let document = PDFDocument(url: url),
                  !document.isLocked,
                  document.pageCount > 0 else { return [] }

            var counts: [String: Int] = [:]
            let pagesToScan = min(document.pageCount, 30)

            for pageIndex in 0..<pagesToScan {
                guard !Task.isCancelled else { return [] }
                guard let page = document.page(at: pageIndex) else { continue }

                let selections = page
                    .selection(for: page.bounds(for: .mediaBox))?
                    .selectionsByLine() ?? []

                for selection in selections {
                    guard let text = selection.string?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                        (2...30).contains(text.count) else { continue }

                    if counts.count < 5_000 || counts[text] != nil {
                        counts[text, default: 0] += 1
                    }
                }
            }

            let threshold = max(2, Int(Double(pagesToScan) * 0.2))
            return counts
                .filter { $0.value >= threshold }
                .map { DetectedWatermark(text: $0.key, occurrenceCount: $0.value) }
                .sorted {
                    if $0.occurrenceCount == $1.occurrenceCount {
                        return $0.text < $1.text
                    }
                    return $0.occurrenceCount > $1.occurrenceCount
                }
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

// MARK: - 单任务 PDF 提取工作器

/// Actor 保证同一个 `PDFDocument` 只被一个串行执行上下文访问，避免 PDFKit 跨线程竞争。
actor PDFExtractionWorker {
    private let document: PDFDocument
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init(document: PDFDocument) {
        self.document = document
    }

    /// 在后台创建专用于本次提取的 PDFDocument，避免与主线程预览共用实例。
    static func make(url: URL) async -> PDFExtractionWorker? {
        let task = Task.detached(priority: .userInitiated) { () -> PDFExtractionWorker? in
            guard let document = PDFDocument(url: url),
                  !document.isLocked,
                  document.pageCount > 0 else { return nil }
            return PDFExtractionWorker(document: document)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func extractPage(
        pageNumber: Int,
        request: PDFExtractionRequest
    ) async -> PageExtractionOutput {
        guard !Task.isCancelled else {
            let empty = ExtractedPageContent(pageNumber: pageNumber, fullText: "", elements: [], images: [])
            return PageExtractionOutput(content: empty, warning: nil)
        }
        guard let page = document.page(at: pageNumber - 1) else {
            let empty = ExtractedPageContent(pageNumber: pageNumber, fullText: "", elements: [], images: [])
            return PageExtractionOutput(
                content: empty,
                warning: "第 \(pageNumber) 页不存在或无法读取。"
            )
        }

        let selections = page
            .selection(for: page.bounds(for: .mediaBox))?
            .selectionsByLine() ?? []

        if request.scenario.extractionMode == .ocrOnly {
            return await extractUsingOCR(
                page: page,
                pageNumber: pageNumber,
                selections: selections,
                request: request
            )
        }

        let pageBounds = page.bounds(for: .mediaBox)
        var renderedCG: CGImage?
        autoreleasepool {
            renderedCG = renderPageToCGImage(page: page, watermarkSelections: [])
        }

        var textBlocks: [DocumentLayoutAnalyzer.TextBlockInfo] = []
        let scale: CGFloat = 2.0

        for sel in selections {
            guard let text = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            if exactlyMatchesWatermark(text: text, filters: request.watermarkFilters, ignoreCase: request.ignoreCase) {
                continue
            }
            let selBounds = sel.bounds(for: page)
            let topY = max(0, (pageBounds.height - selBounds.maxY) * scale)
            let rect = CGRect(
                x: selBounds.minX * scale,
                y: topY,
                width: max(1, selBounds.width * scale),
                height: max(1, selBounds.height * scale)
            )
            textBlocks.append(DocumentLayoutAnalyzer.TextBlockInfo(text: text, yPosition: topY, rect: rect))
        }

        if let cgImage = renderedCG {
            let content = autoreleasepool {
                DocumentLayoutAnalyzer.analyzePage(
                    pageNumber: pageNumber,
                    pageImage: cgImage,
                    textBlocks: textBlocks,
                    watermarks: request.watermarkFilters
                )
            }
            let formattedText = ParagraphReconstructor.reconstruct(content.fullText)
            let finalContent = ExtractedPageContent(
                pageNumber: pageNumber,
                fullText: formattedText,
                elements: content.elements,
                images: content.images
            )
            return PageExtractionOutput(content: finalContent, warning: nil)
        } else {
            let rawText = extractTextLayer(selections: selections, request: request)
            let formattedText = ParagraphReconstructor.reconstruct(rawText)
            let content = ExtractedPageContent(
                pageNumber: pageNumber,
                fullText: formattedText,
                elements: [.paragraph(formattedText)],
                images: []
            )
            return PageExtractionOutput(content: content, warning: nil)
        }
    }

    private func extractUsingOCR(
        page: PDFPage,
        pageNumber: Int,
        selections: [PDFSelection],
        request: PDFExtractionRequest
    ) async -> PageExtractionOutput {
        var rawImage: CGImage?

        // 使用自动释放池包裹位图生成，防止连续 OCR 图像缓冲暴涨
        autoreleasepool {
            var selectionsToCover: [PDFSelection] = []

            if request.scenario == .scannedTextWithTextWatermark,
               request.eraseImageWatermark,
               !request.watermarkFilters.isEmpty {
                selectionsToCover = selections.filter { selection in
                    guard let text = selection.string else { return false }
                    return containsWatermark(
                        text: text,
                        filters: request.watermarkFilters,
                        ignoreCase: request.ignoreCase
                    )
                }
            }

            rawImage = renderPageToCGImage(
                page: page,
                watermarkSelections: selectionsToCover
            )
        }

        guard let initialImage = rawImage else {
            let empty = ExtractedPageContent(pageNumber: pageNumber, fullText: "", elements: [], images: [])
            return PageExtractionOutput(
                content: empty,
                warning: "第 \(pageNumber) 页无法渲染为图像，OCR 已跳过。"
            )
        }

        // 应用 Core Image 滤镜进行色阶与色彩预处理（抹除浅灰水印或彩色印章）
        let processedImage: CGImage
        if request.removeLightWatermarks || request.removeColorStamps {
            processedImage = autoreleasepool {
                applyImageWatermarkFilters(
                    to: initialImage,
                    removeLightWatermarks: request.removeLightWatermarks,
                    removeColorStamps: request.removeColorStamps
                ) ?? initialImage
            }
        } else {
            processedImage = initialImage
        }

        let ocrOutput = await performLocalOCR(on: processedImage)
        guard !Task.isCancelled else {
            let empty = ExtractedPageContent(pageNumber: pageNumber, fullText: "", elements: [], images: [])
            return PageExtractionOutput(content: empty, warning: nil)
        }

        var textBlocks: [DocumentLayoutAnalyzer.TextBlockInfo] = []
        for line in ocrOutput.lines {
            let cleaned = cleanOCRText(
                line.text,
                filters: request.watermarkFilters,
                ignoreCase: request.ignoreCase
            )
            if !cleaned.isEmpty {
                textBlocks.append(DocumentLayoutAnalyzer.TextBlockInfo(
                    text: cleaned,
                    yPosition: line.rect.minY,
                    rect: line.rect
                ))
            }
        }

        // 版面自适应分析：检测插图并与文字按纵向阅读顺序自然混排
        let content = autoreleasepool {
            DocumentLayoutAnalyzer.analyzePage(
                pageNumber: pageNumber,
                pageImage: processedImage,
                textBlocks: textBlocks,
                watermarks: request.watermarkFilters
            )
        }

        let formattedText = ParagraphReconstructor.reconstruct(content.fullText)
        let finalContent = ExtractedPageContent(
            pageNumber: pageNumber,
            fullText: formattedText,
            elements: content.elements,
            images: content.images
        )

        let warning = ocrOutput.warning.map {
            "第 \(pageNumber) 页 OCR 失败：\($0)"
        }
        return PageExtractionOutput(content: finalContent, warning: warning)
    }

    /// 文本层只删除整行完全匹配的水印，避免误删正文中恰好包含同一词语的句子。
    private func extractTextLayer(
        selections: [PDFSelection],
        request: PDFExtractionRequest
    ) -> String {
        var textLines: [String] = []
        var previousLineWasEmpty = false

        for selection in selections {
            guard let text = selection.string else { continue }
            if exactlyMatchesWatermark(
                text: text,
                filters: request.watermarkFilters,
                ignoreCase: request.ignoreCase
            ) {
                continue
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !previousLineWasEmpty {
                    textLines.append("")
                    previousLineWasEmpty = true
                }
            } else {
                textLines.append(text)
                previousLineWasEmpty = false
            }
        }
        return textLines.joined(separator: "\n")
    }

    private func containsWatermark(
        text: String,
        filters: Set<String>,
        ignoreCase: Bool
    ) -> Bool {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return false }
        let options: String.CompareOptions = ignoreCase ? [.caseInsensitive] : []
        return filters.contains { filter in
            cleanedText.range(of: filter, options: options) != nil
        }
    }

    private func exactlyMatchesWatermark(
        text: String,
        filters: Set<String>,
        ignoreCase: Bool
    ) -> Bool {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return false }
        let options: String.CompareOptions = ignoreCase ? [.caseInsensitive] : []
        return filters.contains { filter in
            cleanedText.compare(filter, options: options) == .orderedSame
        }
    }

    /// OCR 结果过滤水印残留，严格限定仅过滤独立行或长词，避免误伤正文短词。
    private func cleanOCRText(
        _ text: String,
        filters: Set<String>,
        ignoreCase: Bool
    ) -> String {
        var cleanedText = text
        let options: String.CompareOptions = ignoreCase ? [.caseInsensitive] : []

        for filter in filters where filter.count >= 2 {
            cleanedText = cleanedText.replacingOccurrences(
                of: filter,
                with: "",
                options: options
            )
        }

        var normalizedLines: [String] = []
        var previousLineWasEmpty = false
        for line in cleanedText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !previousLineWasEmpty {
                    normalizedLines.append("")
                    previousLineWasEmpty = true
                }
            } else {
                normalizedLines.append(line)
                previousLineWasEmpty = false
            }
        }
        return normalizedLines.joined(separator: "\n")
    }

    /// 借鉴专业文档扫描方案，使用 Core Image 执行通道投影与色阶拉伸。
    /// 红色印章在红通道投影下融于白纸，浅灰水印被对比度压平为纯白，黑字保持清晰。
    private func applyImageWatermarkFilters(
        to image: CGImage,
        removeLightWatermarks: Bool,
        removeColorStamps: Bool
    ) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let filtered = DocumentImageFilter.process(
            ciImage,
            removeLightWatermarks: removeLightWatermarks,
            removeColorStamps: removeColorStamps
        )
        return ciContext.createCGImage(filtered, from: filtered.extent)
    }

    /// 将页面最长边限制在 4,096 像素，单页 RGBA 缓冲上限约为 64 MiB。
    private func renderPageToCGImage(
        page: PDFPage,
        watermarkSelections: [PDFSelection]
    ) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let maximumPageDimension = max(pageBounds.width, pageBounds.height)
        guard pageBounds.width.isFinite,
              pageBounds.height.isFinite,
              maximumPageDimension > 0 else { return nil }

        let scale = min(3, 4_096 / maximumPageDimension)
        let pixelWidth = max(1, Int((pageBounds.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((pageBounds.height * scale).rounded(.up)))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphicsContext

        let drawingRect = NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        NSColor.white.setFill()
        drawingRect.fill()

        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        page.draw(with: .mediaBox, to: graphicsContext.cgContext)

        NSColor.white.setFill()
        for selection in watermarkSelections {
            selection.bounds(for: page)
                .insetBy(dx: -1.5, dy: -1.5)
                .fill()
        }
        return bitmap.cgImage
    }

    /// Vision 回调通过 continuation 转为异步返回，避免阻塞主线程等待识别结果。
    private func performLocalOCR(on image: CGImage) async -> OCRExtractionOutput {
        await withCheckedContinuation { continuation in
            let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(
                        returning: OCRExtractionOutput(lines: [], fullText: "", warning: error.localizedDescription)
                    )
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(
                        returning: OCRExtractionOutput(
                            lines: [],
                            fullText: "",
                            warning: "Vision 未返回可解析的文本结果。"
                        )
                    )
                    return
                }

                let imageWidth = CGFloat(image.width)
                let imageHeight = CGFloat(image.height)

                var lines: [OCRLineInfo] = []
                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first?.string else { continue }
                    // Vision boundingBox: origin (0..1, 0..1) at bottom-left
                    let boxX = obs.boundingBox.minX * imageWidth
                    let boxY = (1.0 - obs.boundingBox.maxY) * imageHeight
                    let boxW = obs.boundingBox.width * imageWidth
                    let boxH = obs.boundingBox.height * imageHeight
                    let rect = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)
                    lines.append(OCRLineInfo(text: candidate, rect: rect))
                }

                let fullText = lines.map { $0.text }.joined(separator: "\n")
                continuation.resume(
                    returning: OCRExtractionOutput(lines: lines, fullText: fullText, warning: nil)
                )
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(
                    returning: OCRExtractionOutput(lines: [], fullText: "", warning: error.localizedDescription)
                )
            }
        }
    }
}

// MARK: - 科学级文档图像去水印与印章滤镜
enum DocumentImageFilter {
    /// 对图像执行色彩通道投影与色阶提亮
    /// - 彩色印章消除：基于红通道投影（红色印章在红通道反射率高，与白纸融为一体，黑字吸光保持深黑），彻底避免单纯转灰度导致的文字污染
    /// - 浅灰水印消除：通过高对比度和曝光度拉伸，将浅灰与杂印推入纯白 (255)
    static func process(
        _ ciImage: CIImage,
        removeLightWatermarks: Bool,
        removeColorStamps: Bool
    ) -> CIImage {
        var output = ciImage

        // 1. 彩色印章消除：基于红通道投影，将红色印章与白底同化
        if removeColorStamps {
            if let matrix = CIFilter(name: "CIColorMatrix") {
                matrix.setValue(output, forKey: kCIInputImageKey)
                matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputGVector")
                matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputBVector")
                matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
                matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                if let matrixOutput = matrix.outputImage {
                    output = matrixOutput
                }
            }
        }

        // 2. 浅灰底纹/杂色消除：拉伸对比度与亮度，将浅灰背景推至纯白
        if removeLightWatermarks {
            if let colorControls = CIFilter(name: "CIColorControls") {
                colorControls.setValue(output, forKey: kCIInputImageKey)
                colorControls.setValue(1.5, forKey: kCIInputContrastKey)
                colorControls.setValue(0.14, forKey: kCIInputBrightnessKey)
                if let controlsOutput = colorControls.outputImage {
                    output = controlsOutput
                }
            }
        }

        return output
    }
}

// MARK: - 页面缩略图与去水印对比预览生成器
enum PDFThumbnailLoader {
    /// 异步生成指定页面的轻量缩略图
    static func thumbnail(for page: PDFPage, targetWidth: CGFloat = 160) -> NSImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = targetWidth / bounds.width
        let targetHeight = bounds.height * scale
        return page.thumbnail(of: NSSize(width: targetWidth, height: targetHeight), for: .mediaBox)
    }

    /// 针对 Core Image 图像去水印生成预览对比图像 (Before / After)
    static func watermarkComparisonPreview(
        for page: PDFPage,
        removeLightWatermarks: Bool,
        removeColorStamps: Bool
    ) -> (original: NSImage, filtered: NSImage)? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let originalThumbnail = page.thumbnail(of: NSSize(width: 400, height: 400 * bounds.height / bounds.width), for: .mediaBox)

        guard let tiffData = originalThumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        let processedCIImage = DocumentImageFilter.process(
            ciImage,
            removeLightWatermarks: removeLightWatermarks,
            removeColorStamps: removeColorStamps
        )
        
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        guard let filteredCGImage = ciContext.createCGImage(processedCIImage, from: processedCIImage.extent) else {
            return nil
        }
        let filteredImage = NSImage(cgImage: filteredCGImage, size: originalThumbnail.size)
        return (original: originalThumbnail, filtered: filteredImage)
    }
}

