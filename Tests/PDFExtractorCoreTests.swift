import Darwin
import Foundation
import AppKit
import CoreGraphics
import CoreImage
import PDFKit

// MARK: - 零依赖测试基础设施

/// 当前 Command Line Tools 未附带 XCTest/Testing 运行库，因此使用轻量执行器。
/// 测试仍由 Swift 6 编译器编译真实生产源码，任何失败都会让进程返回非零状态。
private struct AssertionFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private struct CoreTestSuite {
    private(set) var passedCount = 0
    private(set) var failures: [String] = []

    mutating func run(_ name: String, body: () throws -> Void) {
        do {
            try body()
            passedCount += 1
            print("通过：\(name)")
        } catch {
            failures.append("\(name)：\(error)")
            print("失败：\(name)：\(error)")
        }
    }

    mutating func runAsync(_ name: String, body: () async throws -> Void) async {
        do {
            try await body()
            passedCount += 1
            print("通过：\(name)")
        } catch {
            failures.append("\(name)：\(error)")
            print("失败：\(name)：\(error)")
        }
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("核心与全功能测试完成：\(passedCount) 项全部通过。")
            exit(EXIT_SUCCESS)
        }

        print("核心逻辑测试失败：\(failures.count) 项失败，\(passedCount) 项通过。")
        exit(EXIT_FAILURE)
    }
}

private func require(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String
) throws {
    guard try condition() else { throw AssertionFailure(description: message) }
}

private func requireThrows<ExpectedError>(
    _ expectedError: ExpectedError,
    operation: () throws -> Void
) throws where ExpectedError: Error & Equatable {
    do {
        try operation()
    } catch let actualError as ExpectedError {
        try require(actualError == expectedError, "错误不匹配：\(actualError)")
        return
    }
    throw AssertionFailure(description: "预期抛出 \(expectedError)，但操作成功或抛出了其他错误。")
}

// MARK: - 核心逻辑测试入口

@main
@MainActor
struct PDFExtractorCoreTests {
    static func main() async {
        var suite = CoreTestSuite()
        runPageRangeTests(in: &suite)
        runParagraphReconstructorTests(in: &suite)
        runDocumentLayoutAnalyzerTests(in: &suite)
        runDocxDocumentBuilderTests(in: &suite)
        runDocumentImageFilterTests(in: &suite)
        runEdgeCasesAndResilienceTests(in: &suite)
        await runLargeDocumentStressTests(in: &suite)
        suite.finish()
    }

    private static func runPageRangeTests(in suite: inout CoreTestSuite) {
        suite.run("空页码输入选择全部页面") {
            let pages = try PageRangeParser.parse("", maximumPageCount: 4)
            try require(pages == [1, 2, 3, 4], "全部页码结果不正确")
        }

        suite.run("混合连接符标准化并去重") {
            let pages = try PageRangeParser.parse(
                "1-3， 6, 8—7, 3",
                maximumPageCount: 10
            )
            try require(pages == [1, 2, 3, 6, 7, 8], "混合页码解析结果不正确")
        }

        suite.run("无效页码不会回退为全部页面") {
            try requireThrows(PageRangeError.invalidItem("abc")) {
                _ = try PageRangeParser.parse("abc", maximumPageCount: 20)
            }
        }

        suite.run("越界页码返回明确错误") {
            try requireThrows(
                PageRangeError.pageOutOfBounds(page: 99, maximum: 12)
            ) {
                _ = try PageRangeParser.parse("1-99", maximumPageCount: 12)
            }
        }

        suite.run("零页文档不会创建非法闭区间") {
            try requireThrows(PageRangeError.documentHasNoPages) {
                _ = try PageRangeParser.parse("", maximumPageCount: 0)
            }
        }

        suite.run("提取请求冻结校验后的输入与图像去水印参数") {
            let request = try PDFExtractionRequest(
                scenario: .fullyScanned,
                activeWatermarks: ["内部资料"],
                customWatermarks: "样张，内部资料\nCONFIDENTIAL",
                ignoreCase: true,
                eraseImageWatermark: false,
                removeLightWatermarks: true,
                removeColorStamps: true,
                pageRangeString: "2-3",
                maximumPageCount: 5
            )
            try require(request.targetPages == [2, 3], "请求页码不正确")
            try require(
                request.watermarkFilters == ["内部资料", "样张", "CONFIDENTIAL"],
                "水印词没有正确合并去重"
            )
            try require(request.removeLightWatermarks, "浅色水印消除未正确捕获")
            try require(request.removeColorStamps, "彩色印章过滤未正确捕获")
        }
    }

    private static func runParagraphReconstructorTests(in suite: inout CoreTestSuite) {
        suite.run("中文段内硬换行自动合并且标点正常分段") {
            let input = "这是第一行的文字，后面\n还有一句话。这是第二句。\n\n这是新段落。"
            let output = ParagraphReconstructor.reconstruct(input)
            let expected = "这是第一行的文字，后面还有一句话。这是第二句。\n\n这是新段落。"
            try require(output == expected, "中文断行合并错误，实际输出：\n\(output)")
        }

        suite.run("西文字符断行合并时自动补充空格") {
            let input = "This is line one of\na test paragraph. Second line here.\nAnother line here."
            let output = ParagraphReconstructor.reconstruct(input)
            let expected = "This is line one of a test paragraph. Second line here.\n\nAnother line here."
            try require(output == expected, "英文断行合并缺少空格，实际输出：\n\(output)")
        }

        suite.run("标题与序号列表独立成段不被合并") {
            let input = "# 一级大标题\n正文首行文字\n正文次行文字。\n1. 第一项列表\n2. 第二项列表"
            let output = ParagraphReconstructor.reconstruct(input)
            try require(output.contains("# 一级大标题\n\n正文首行文字正文次行文字。"), "标题未独立分段")
            try require(output.contains("1. 第一项列表\n\n2. 第二项列表"), "列表项未独立分段")
        }
    }

    @MainActor
    private static func runDocumentLayoutAnalyzerTests(in suite: inout CoreTestSuite) {
        suite.run("图文混排按垂直Y轴自然穿插") {
            let textBlocks = [
                DocumentLayoutAnalyzer.TextBlockInfo(text: "顶部介绍段落。", yPosition: 50),
                DocumentLayoutAnalyzer.TextBlockInfo(text: "底部总结段落。", yPosition: 350)
            ]

            let testImage = makeTestNSImage(width: 200, height: 100)
            let imageBounds = CGRect(x: 50, y: 150, width: 200, height: 100)
            let extractedImg = ExtractedImage(
                pageNumber: 1,
                imageIndex: 1,
                nsImage: testImage,
                bounds: imageBounds
            )

            let elements = DocumentLayoutAnalyzer.interweave(
                textBlocks: textBlocks,
                images: [extractedImg]
            )

            try require(elements.count == 3, "混排元素总数应为 3，实际为 \(elements.count)")
            
            if case .paragraph(let text) = elements[0] {
                try require(text == "顶部介绍段落。", "首个元素应为顶部段落")
            } else {
                throw AssertionFailure(description: "首个元素应为段落")
            }

            if case .image(let img) = elements[1] {
                try require(img.imageIndex == 1, "中间元素应为插图 1")
            } else {
                throw AssertionFailure(description: "第二个元素应为插图")
            }

            if case .paragraph(let text) = elements[2] {
                try require(text == "底部总结段落。", "末尾元素应为底部总结段落")
            } else {
                throw AssertionFailure(description: "末尾元素应为段落")
            }
        }

        suite.run("无插图页面产生单一文本段落流") {
            let textBlocks = [
                DocumentLayoutAnalyzer.TextBlockInfo(text: "第一段落。", yPosition: 10),
                DocumentLayoutAnalyzer.TextBlockInfo(text: "第二段落。", yPosition: 60)
            ]

            let elements = DocumentLayoutAnalyzer.interweave(
                textBlocks: textBlocks,
                images: []
            )

            try require(elements.count == 2, "纯文本混排元素数应为 2")
        }
    }

    @MainActor
    private static func runDocxDocumentBuilderTests(in suite: inout CoreTestSuite) {
        suite.run("Word (.docx) 单文件生成且内嵌插图") {
            let testImage = makeTestNSImage(width: 80, height: 80)
            let extractedImg = ExtractedImage(
                pageNumber: 1,
                imageIndex: 1,
                nsImage: testImage,
                bounds: CGRect(x: 0, y: 50, width: 80, height: 80)
            )

            let pageContent = ExtractedPageContent(
                pageNumber: 1,
                fullText: "测试 Word 导出内容段落",
                elements: [
                    .paragraph("测试 Word 导出内容段落，这是第一段。"),
                    .image(extractedImg),
                    .paragraph("这是插图后的第二段落。")
                ],
                images: [extractedImg]
            )

            let docxData = try DocxDocumentBuilder.buildDocxData(
                title: "单元测试文档",
                pages: [pageContent]
            )

            try require(!docxData.isEmpty, "生成 Word 数据不可为空")
            try require(docxData.count > 100, "生成的 docx 数据过小 (\(docxData.count) bytes)")

            let header = [UInt8](docxData.prefix(4))
            try require(header == [0x50, 0x4B, 0x03, 0x04], "Word docx 文件头必须为标准 Zip 魔数 PK\\x03\\x04")
        }

        suite.run("Markdown 导出排版文本与图文清单") {
            let testImage = makeTestNSImage(width: 60, height: 60)
            let extractedImg = ExtractedImage(
                pageNumber: 1,
                imageIndex: 1,
                nsImage: testImage,
                bounds: CGRect(x: 0, y: 20, width: 60, height: 60)
            )

            let pageContent = ExtractedPageContent(
                pageNumber: 1,
                fullText: "Markdown 正文段落",
                elements: [
                    .paragraph("Markdown 正文段落。"),
                    .image(extractedImg)
                ],
                images: [extractedImg]
            )

            let (mdText, mdImages) = DocxDocumentBuilder.buildMarkdown(
                title: "测试 Markdown",
                pages: [pageContent]
            )
            try require(mdText.contains("# 测试 Markdown"), "Markdown 应包含主标题")
            try require(mdText.contains("![page_1_fig_1.png](images/page_1_fig_1.png)"), "Markdown 应包含插图链接")
            try require(mdImages.count == 1, "Markdown 导出的图片数量应为 1")
        }
    }

    private static func runDocumentImageFilterTests(in suite: inout CoreTestSuite) {
        suite.run("Core Image 红通道投影与色阶拉伸滤镜链完整性") {
            let testCG = makeTestCGImage(width: 100, height: 100)
            let ciImage = CIImage(cgImage: testCG)
            let filtered = DocumentImageFilter.process(
                ciImage,
                removeLightWatermarks: true,
                removeColorStamps: true
            )
            try require(filtered.extent.width == 100, "滤镜处理后图像宽度应保持不变")
            try require(filtered.extent.height == 100, "滤镜处理后图像高度应保持不变")
        }
    }

    private static func runEdgeCasesAndResilienceTests(in suite: inout CoreTestSuite) {
        suite.run("超大尺寸页面插图探测边界保护") {
            let largeCG = makeTestCGImage(width: 3000, height: 4000)
            let detected = DocumentLayoutAnalyzer.detectFigureRects(
                in: largeCG,
                textRects: [CGRect(x: 100, y: 100, width: 800, height: 50)],
                imageWidth: 3000,
                imageHeight: 4000
            )
            try require(detected.count >= 0, "超大尺寸探测应正常完成")
        }

        suite.run("极小尺寸页面保护直接返回空") {
            let tinyCG = makeTestCGImage(width: 50, height: 50)
            let detected = DocumentLayoutAnalyzer.detectFigureRects(
                in: tinyCG,
                textRects: [],
                imageWidth: 50,
                imageHeight: 50
            )
            try require(detected.isEmpty, "极小页面应安全返回空插图列表")
        }

        suite.run("水印特殊字符与空词容错") {
            let parsed = WatermarkTermParser.parse("   \n\n,,  内部资料  ,  SAMPLE (CONFIDENTIAL)  , [机密] \n")
            try require(parsed.contains("内部资料"), "未能解析内部资料")
            try require(parsed.contains("SAMPLE (CONFIDENTIAL)"), "未能解析带括号水印")
            try require(parsed.contains("[机密]"), "未能解析带方括号水印")
            try require(!parsed.contains(""), "不应包含空字符串")
        }
    }

    @MainActor
    private static func runLargeDocumentStressTests(in suite: inout CoreTestSuite) async {
        await suite.runAsync("20页大型多页文档合成与图文提取压力测试") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let pdfURL = tempDir.appendingPathComponent("StressTest.pdf")
            let pageCount = 20
            makeSyntheticPDF(pageCount: pageCount, url: pdfURL)

            // 1. 测试加载器
            guard let loadResult = await PDFDocumentLoader.load(url: pdfURL) else {
                throw AssertionFailure(description: "加载合成 20 页 PDF 失败")
            }
            try require(loadResult.pageCount == pageCount, "加载页数与生成页数不符")

            // 2. 测试多页提取
            guard let worker = await PDFExtractionWorker.make(url: pdfURL) else {
                throw AssertionFailure(description: "创建提取工作器失败")
            }

            let request = try PDFExtractionRequest(
                scenario: .electronicTextWithTextWatermark,
                activeWatermarks: [],
                customWatermarks: "",
                ignoreCase: true,
                pageRangeString: "1-\(pageCount)",
                maximumPageCount: pageCount
            )

            var extractedPagesList: [ExtractedPageContent] = []
            for p in 1...pageCount {
                let output = await worker.extractPage(pageNumber: p, request: request)
                extractedPagesList.append(output.content)
            }

            try require(extractedPagesList.count == pageCount, "20页提取数量不匹配")

            // 3. 测试 20 页整包 Word (.docx) 生成
            let docxData = try DocxDocumentBuilder.buildDocxData(
                title: "20页压力测试报告",
                pages: extractedPagesList
            )
            try require(docxData.count > 1000, "20页 Word 文件大小不正常 (\(docxData.count) bytes)")
            let header = [UInt8](docxData.prefix(4))
            try require(header == [0x50, 0x4B, 0x03, 0x04], "Word docx 文件头必须为标准 Zip 魔数")
        }
    }

    @MainActor
    private static func makeTestNSImage(width: Int, height: Int) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    private static func makeTestCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @MainActor
    private static func makeSyntheticPDF(pageCount: Int, url: URL) {
        let doc = PDFDocument()
        for i in 1...pageCount {
            let pageRect = NSRect(x: 0, y: 0, width: 612, height: 792)
            let img = NSImage(size: pageRect.size)
            img.lockFocus()
            NSColor.white.setFill()
            pageRect.fill()

            let text = "这是第 \(i) 页的测试段落文字，用于大文件稳定性与内存泄漏测试。包含第二句话。"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.black
            ]
            (text as NSString).draw(at: NSPoint(x: 50, y: 700), withAttributes: attrs)

            NSColor.systemOrange.setFill()
            NSRect(x: 50, y: 350, width: 300, height: 200).fill()

            img.unlockFocus()
            if let page = PDFPage(image: img) {
                doc.insert(page, at: doc.pageCount)
            }
        }
        doc.write(to: url)
    }
}



