import Foundation
import AppKit

// MARK: - 原生 Word 文档 (.docx) 与 Markdown 生成器

public enum DocxDocumentBuilder {

    /// 将多页图文混排内容生成为标准的 Microsoft Word (.docx) 二进制数据，图片无损内嵌在单一文档中
    public static func buildDocxData(
        title: String,
        pages: [ExtractedPageContent]
    ) throws -> Data {
        let attr = NSMutableAttributedString()

        // 1. 文档大标题
        let titleParagraphStyle = NSMutableParagraphStyle()
        titleParagraphStyle.alignment = .center
        titleParagraphStyle.paragraphSpacing = 22
        titleParagraphStyle.lineSpacing = 4

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 20),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: titleParagraphStyle
        ]
        attr.append(NSAttributedString(string: "\(title)\n\n", attributes: titleAttrs))

        // 2. 依次加入各页排版内容
        let bodyParagraphStyle = NSMutableParagraphStyle()
        bodyParagraphStyle.lineSpacing = 5
        bodyParagraphStyle.paragraphSpacing = 14
        bodyParagraphStyle.firstLineHeadIndent = 0

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: bodyParagraphStyle
        ]

        let pageHeadingStyle = NSMutableParagraphStyle()
        pageHeadingStyle.paragraphSpacing = 10
        pageHeadingStyle.paragraphSpacingBefore = 18

        let pageHeadingAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: pageHeadingStyle
        ]

        let sortedPages = pages.sorted { $0.pageNumber < $1.pageNumber }

        for (pageIndex, page) in sortedPages.enumerated() {
            // 多页文档添加页眉小标记
            if sortedPages.count > 1 {
                attr.append(NSAttributedString(string: "--- 第 \(page.pageNumber) 页 ---\n", attributes: pageHeadingAttrs))
            }

            for element in page.elements {
                switch element {
                case .paragraph(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    attr.append(NSAttributedString(string: "\(trimmed)\n\n", attributes: bodyAttrs))

                case .image(let extImg):
                    // 调整 Word 页面中的图片合适宽度（不超过 480pt，保持比例）
                    let originalSize = extImg.nsImage.size
                    let maxDisplayWidth: CGFloat = 480
                    let displaySize: NSSize
                    if originalSize.width > maxDisplayWidth {
                        let scale = maxDisplayWidth / originalSize.width
                        displaySize = NSSize(width: maxDisplayWidth, height: max(1, originalSize.height * scale))
                    } else if originalSize.width > 0 && originalSize.height > 0 {
                        displaySize = originalSize
                    } else {
                        displaySize = NSSize(width: 300, height: 200)
                    }

                    let attachment = NSTextAttachment()
                    let scaledImg = NSImage(size: displaySize)
                    scaledImg.lockFocus()
                    extImg.nsImage.draw(
                        in: NSRect(origin: .zero, size: displaySize),
                        from: NSRect(origin: .zero, size: originalSize),
                        operation: .copy,
                        fraction: 1.0
                    )
                    scaledImg.unlockFocus()

                    attachment.image = scaledImg

                    let imageParagraphStyle = NSMutableParagraphStyle()
                    imageParagraphStyle.alignment = .center
                    imageParagraphStyle.paragraphSpacing = 16
                    imageParagraphStyle.paragraphSpacingBefore = 8

                    let imageAttr = NSMutableAttributedString(attachment: attachment)
                    imageAttr.addAttributes([.paragraphStyle: imageParagraphStyle], range: NSRange(location: 0, length: imageAttr.length))

                    attr.append(imageAttr)
                    attr.append(NSAttributedString(string: "\n\n", attributes: bodyAttrs))
                }
            }

            if pageIndex < sortedPages.count - 1 {
                attr.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
            }
        }

        // 利用 macOS 原生 OfficeOpenXML 生成器导出标准 Microsoft Word (.docx)
        return try attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.officeOpenXML,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
        )
    }

    /// 生成 Markdown 文本以及关联图片清单
    public static func buildMarkdown(
        title: String,
        pages: [ExtractedPageContent],
        imageRelativePathPrefix: String = "images"
    ) -> (markdown: String, images: [(filename: String, image: NSImage)]) {
        var lines: [String] = ["# \(title)", ""]
        var exportedImages: [(filename: String, image: NSImage)] = []

        let sortedPages = pages.sorted { $0.pageNumber < $1.pageNumber }

        for page in sortedPages {
            if sortedPages.count > 1 {
                lines.append("## 第 \(page.pageNumber) 页")
                lines.append("")
            }

            for element in page.elements {
                switch element {
                case .paragraph(let text):
                    lines.append(text)
                    lines.append("")
                case .image(let img):
                    let filename = "page_\(img.pageNumber)_fig_\(img.imageIndex).png"
                    exportedImages.append((filename, img.nsImage))
                    let imagePath = imageRelativePathPrefix.isEmpty ? filename : "\(imageRelativePathPrefix)/\(filename)"
                    lines.append("![\(filename)](\(imagePath))")
                    lines.append("")
                }
            }
        }

        return (lines.joined(separator: "\n"), exportedImages)
    }
}
