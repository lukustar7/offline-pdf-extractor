import Foundation
import AppKit
import CoreGraphics

// MARK: - 图文混排数据模型 (Layout & Element Models)

/// 单张从页面截取的图片模型
public struct ExtractedImage: Identifiable, Sendable {
    public let id: UUID
    public let pageNumber: Int
    public let imageIndex: Int
    public let nsImage: NSImage
    public let bounds: CGRect // 页面顶部原点坐标系的边界矩形

    public init(id: UUID = UUID(), pageNumber: Int, imageIndex: Int, nsImage: NSImage, bounds: CGRect) {
        self.id = id
        self.pageNumber = pageNumber
        self.imageIndex = imageIndex
        self.nsImage = nsImage
        self.bounds = bounds
    }
}

/// 页面文档流中的元素（自然段落文字或高清插图）
public enum DocumentElement: Identifiable, Sendable {
    case paragraph(String)
    case image(ExtractedImage)

    public var id: String {
        switch self {
        case .paragraph(let text):
            return "p_\(text.hashValue)"
        case .image(let img):
            return "img_\(img.id.uuidString)"
        }
    }

    public var textContent: String {
        switch self {
        case .paragraph(let text):
            return text
        case .image:
            return ""
        }
    }
}

/// 单页完整提取成果（包含段落、插图与图文混排流）
public struct ExtractedPageContent: Sendable {
    public let pageNumber: Int
    public let fullText: String
    public let elements: [DocumentElement]
    public let images: [ExtractedImage]

    public init(pageNumber: Int, fullText: String, elements: [DocumentElement], images: [ExtractedImage]) {
        self.pageNumber = pageNumber
        self.fullText = fullText
        self.elements = elements
        self.images = images
    }
}

// MARK: - 版面自适应插图定位与混排分析器

public enum DocumentLayoutAnalyzer {

    /// 文本块与在页面中的垂直位置信息
    public struct TextBlockInfo: Sendable {
        public let text: String
        public let yPosition: CGFloat // 距页面顶部的距离
        public let rect: CGRect // 页面顶部原点坐标

        public init(text: String, yPosition: CGFloat, rect: CGRect = .zero) {
            self.text = text
            self.yPosition = yPosition
            self.rect = rect
        }
    }

    /// 在给定整页高清渲染位图与已知文本行边界时，自动检测插图/图表区域并截取，并按阅读顺序将图文混排。
    public static func analyzePage(
        pageNumber: Int,
        pageImage: CGImage,
        textBlocks: [TextBlockInfo],
        watermarks: Set<String> = []
    ) -> ExtractedPageContent {
        let imageWidth = CGFloat(pageImage.width)
        let imageHeight = CGFloat(pageImage.height)

        // 1. 检测非文字区域的大块插图 / 图表
        let detectedRects = detectFigureRects(
            in: pageImage,
            textRects: textBlocks.map { $0.rect },
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )

        // 2. 裁剪对应的高清插图
        var extractedImages: [ExtractedImage] = []
        for (index, rect) in detectedRects.enumerated() {
            if let croppedCG = pageImage.cropping(to: rect) {
                let nsImg = NSImage(cgImage: croppedCG, size: NSSize(width: rect.width / 2.0, height: rect.height / 2.0))
                let extImg = ExtractedImage(
                    pageNumber: pageNumber,
                    imageIndex: index + 1,
                    nsImage: nsImg,
                    bounds: rect
                )
                extractedImages.append(extImg)
            }
        }

        // 3. 将段落与插图按在页面自上而下的纵向 Y 坐标统一排序，形成自然阅读流
        let elements = interweave(textBlocks: textBlocks, images: extractedImages)
        let fullText = elements.compactMap { element -> String? in
            switch element {
            case .paragraph(let text):
                return text
            case .image:
                return nil
            }
        }.joined(separator: "\n\n")

        return ExtractedPageContent(
            pageNumber: pageNumber,
            fullText: fullText,
            elements: elements,
            images: extractedImages
        )
    }

    /// 将文本段落与插图按在页面自上而下的纵向 Y 坐标统一排序，形成自然阅读流
    public static func interweave(
        textBlocks: [TextBlockInfo],
        images: [ExtractedImage]
    ) -> [DocumentElement] {
        struct SortableItem {
            let yPosition: CGFloat
            let element: DocumentElement
        }

        var sortableItems: [SortableItem] = []

        for block in textBlocks {
            let cleaned = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            sortableItems.append(SortableItem(
                yPosition: block.yPosition,
                element: .paragraph(cleaned)
            ))
        }

        for img in images {
            sortableItems.append(SortableItem(
                yPosition: img.bounds.midY,
                element: .image(img)
            ))
        }

        // 按垂直高度升序（从页面顶部到页面底部）
        sortableItems.sort { $0.yPosition < $1.yPosition }

        return sortableItems.map { $0.element }
    }

    // MARK: - 内部算法：文字遮蔽与插图外接矩形探测

    public static func detectFigureRects(
        in image: CGImage,
        textRects: [CGRect],
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [CGRect] {
        guard imageWidth > 100, imageHeight > 100 else { return [] }

        // 使用低分辨率占用网格（网格宽度 120，高度按比例）
        let gridW = 120
        let gridH = max(40, Int(CGFloat(gridW) * (imageHeight / imageWidth)))
        let scaleX = CGFloat(gridW) / imageWidth
        let scaleY = CGFloat(gridH) / imageHeight

        // 1. 标记文字覆盖的网格区域（带 1 格边距扩张，防止把文字边缘当成图）
        var isTextGrid = Array(repeating: Array(repeating: false, count: gridW), count: gridH)
        for rect in textRects {
            let gx = Int(rect.minX * scaleX)
            let gy = Int(rect.minY * scaleY)
            let gw = max(1, Int(rect.width * scaleX))
            let gh = max(1, Int(rect.height * scaleY))

            let startY = max(0, gy - 1)
            let endY = min(gridH - 1, gy + gh + 1)
            let startX = max(0, gx - 1)
            let endX = min(gridW - 1, gx + gw + 1)

            for y in startY...endY {
                for x in startX...endX {
                    isTextGrid[y][x] = true
                }
            }
        }

        // 2. 检查非文字区域中的视觉图形内容（通过低分辨率像素采样）
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return []
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow
        guard bytesPerPixel >= 3 else { return [] }

        var hasContentGrid = Array(repeating: Array(repeating: false, count: gridW), count: gridH)
        var totalContentCells = 0

        for gy in 0..<gridH {
            for gx in 0..<gridW {
                if isTextGrid[gy][gx] { continue }

                let origY = min(Int(imageHeight) - 1, max(0, Int(CGFloat(gy) / scaleY)))
                let origX = min(Int(imageWidth) - 1, max(0, Int(CGFloat(gx) / scaleX)))

                let offset = origY * bytesPerRow + origX * bytesPerPixel
                let r = Int(ptr[offset])
                let g = Int(ptr[offset + 1])
                let b = Int(ptr[offset + 2])

                // 纯白背景过滤：当亮度明显偏离背景白纸（luminance < 238），或者有明显色彩饱和度时，标为内容
                let luminance = (r * 299 + g * 587 + b * 114) / 1000
                let maxChannel = max(r, max(g, b))
                let minChannel = min(r, min(g, b))
                let saturation = maxChannel - minChannel

                if luminance < 238 || saturation > 30 {
                    hasContentGrid[gy][gx] = true
                    totalContentCells += 1
                }
            }
        }

        guard totalContentCells > 15 else { return [] }

        // 3. 连通域外接矩形聚合 (Bounding Box Clustering)
        var visited = Array(repeating: Array(repeating: false, count: gridW), count: gridH)
        var clusters: [CGRect] = []

        for gy in 0..<gridH {
            for gx in 0..<gridW {
                if hasContentGrid[gy][gx] && !visited[gy][gx] {
                    // BFS 寻找连通区域
                    var queue: [(Int, Int)] = [(gx, gy)]
                    visited[gy][gx] = true

                    var minX = gx, maxX = gx
                    var minY = gy, maxY = gy

                    var head = 0
                    while head < queue.count {
                        let (cx, cy) = queue[head]
                        head += 1

                        minX = min(minX, cx)
                        maxX = max(maxX, cx)
                        minY = min(minY, cy)
                        maxY = max(maxY, cy)

                        // 8 邻域扩散（带 2 格容差以合并相连图表）
                        let neighbors = [
                            (cx - 1, cy), (cx + 1, cy),
                            (cx, cy - 1), (cx, cy + 1),
                            (cx - 1, cy - 1), (cx + 1, cy - 1),
                            (cx - 1, cy + 1), (cx + 1, cy + 1),
                            (cx - 2, cy), (cx + 2, cy),
                            (cx, cy - 2), (cx, cy + 2)
                        ]

                        for (nx, ny) in neighbors {
                            if nx >= 0, nx < gridW, ny >= 0, ny < gridH {
                                if hasContentGrid[ny][nx] && !visited[ny][nx] {
                                    visited[ny][nx] = true
                                    queue.append((nx, ny))
                                }
                            }
                        }
                    }

                    // 转换回原图像素坐标
                    let boxX = CGFloat(minX) / scaleX
                    let boxY = CGFloat(minY) / scaleY
                    let boxW = CGFloat(maxX - minX + 1) / scaleX
                    let boxH = CGFloat(maxY - minY + 1) / scaleY

                    // 阈值过滤：剔除杂点、微小噪点。插图至少宽 50、高 40，面积大于 3000
                    if boxW >= 50, boxH >= 40, (boxW * boxH) >= 3000 {
                        let ratio = boxW / boxH
                        if ratio > 0.08 && ratio < 12.0 {
                            let paddedRect = CGRect(
                                x: max(0, boxX - 4),
                                y: max(0, boxY - 4),
                                width: min(imageWidth - boxX, boxW + 8),
                                height: min(imageHeight - boxY, boxH + 8)
                            )
                            clusters.append(paddedRect)
                        }
                    }
                }
            }
        }

        return mergeOverlappingRects(clusters)
    }

    private static func mergeOverlappingRects(_ rects: [CGRect]) -> [CGRect] {
        guard rects.count > 1 else { return rects }
        var result: [CGRect] = []

        for rect in rects {
            var merged = false
            for i in 0..<result.count {
                let expanded = result[i].insetBy(dx: -15, dy: -15)
                if expanded.intersects(rect) {
                    result[i] = result[i].union(rect)
                    merged = true
                    break
                }
            }
            if !merged {
                result.append(rect)
            }
        }

        return result
    }
}
