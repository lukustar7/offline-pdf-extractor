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
}

struct DetectedWatermark: Sendable {
    let text: String
    let occurrenceCount: Int
}

struct PageExtractionOutput: Sendable {
    let text: String
    let warning: String?
}

private struct OCRExtractionOutput: Sendable {
    let text: String
    let warning: String?
}

// MARK: - PDF 后台加载器

/// 将可能较慢的 PDF 初始化与水印词频统计移出主线程。
enum PDFDocumentLoader {
    static func load(url: URL) async -> PDFDocumentLoadResult? {
        let task = Task.detached(priority: .userInitiated) { () -> PDFDocumentLoadResult? in
            guard let document = PDFDocument(url: url) else { return nil }
            return PDFDocumentLoadResult(
                document: document,
                pageCount: document.pageCount,
                isLocked: document.isLocked
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
            return PageExtractionOutput(text: "", warning: nil)
        }
        guard let page = document.page(at: pageNumber - 1) else {
            return PageExtractionOutput(
                text: "",
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

        return PageExtractionOutput(
            text: extractTextLayer(selections: selections, request: request),
            warning: nil
        )
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
            return PageExtractionOutput(
                text: "",
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
            return PageExtractionOutput(text: "", warning: nil)
        }

        let cleanedText = cleanOCRText(
            ocrOutput.text,
            filters: request.watermarkFilters,
            ignoreCase: request.ignoreCase
        )
        let warning = ocrOutput.warning.map {
            "第 \(pageNumber) 页 OCR 失败：\($0)"
        }
        return PageExtractionOutput(text: cleanedText, warning: warning)
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

    /// 借鉴开源成熟方案，使用 macOS 原生 Core Image 对图像执行色阶与色彩预处理。
    /// 浅灰/浅色水印（亮度较高）被拉伸为纯白，深黑字迹保持清晰；彩色印章可转单色过滤。
    private func applyImageWatermarkFilters(
        to image: CGImage,
        removeLightWatermarks: Bool,
        removeColorStamps: Bool
    ) -> CGImage? {
        var ciImage = CIImage(cgImage: image)

        // 1. 如果需要滤除彩色印章，先将图像转为灰度，抹平色相差异
        if removeColorStamps {
            if let grayFilter = CIFilter(name: "CIPhotoEffectMono") {
                grayFilter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = grayFilter.outputImage {
                    ciImage = output
                }
            }
        }

        // 2. 浅色/灰度水印消除：通过提升对比度与曝光度，将背景浅灰（>180）推到纯白（255）
        if removeLightWatermarks {
            if let colorControls = CIFilter(name: "CIColorControls") {
                colorControls.setValue(ciImage, forKey: kCIInputImageKey)
                // 适度增加对比度与亮度，压平背景杂色与浅灰印
                colorControls.setValue(1.45, forKey: kCIInputContrastKey)
                colorControls.setValue(0.12, forKey: kCIInputBrightnessKey)
                if let output = colorControls.outputImage {
                    ciImage = output
                }
            }
        }

        return ciContext.createCGImage(ciImage, from: ciImage.extent)
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
                        returning: OCRExtractionOutput(text: "", warning: error.localizedDescription)
                    )
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(
                        returning: OCRExtractionOutput(
                            text: "",
                            warning: "Vision 未返回可解析的文本结果。"
                        )
                    )
                    return
                }

                let lines = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }
                let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
                continuation.resume(
                    returning: OCRExtractionOutput(text: text, warning: nil)
                )
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(
                    returning: OCRExtractionOutput(text: "", warning: error.localizedDescription)
                )
            }
        }
    }
}
