import Foundation

// MARK: - 页码范围解析

/// 页码输入错误类型。错误会直接展示给用户，不再把错误输入静默降级为“处理全部页面”。
enum PageRangeError: LocalizedError, Equatable, Sendable {
    case documentHasNoPages
    case emptyItem
    case invalidItem(String)
    case pageOutOfBounds(page: Int, maximum: Int)

    var errorDescription: String? {
        switch self {
        case .documentHasNoPages:
            return "当前 PDF 没有可处理的页面。"
        case .emptyItem:
            return "页码范围中存在空白项，请检查多余的逗号。"
        case .invalidItem(let item):
            return "无法识别页码“\(item)”，请按 1-5, 8, 10-12 的格式输入。"
        case .pageOutOfBounds(let page, let maximum):
            return "页码 \(page) 超出范围，当前 PDF 只有 \(maximum) 页。"
        }
    }
}

/// 将用户输入转换为去重、升序的物理页码数组。
enum PageRangeParser {
    /// 支持中英文逗号，以及常见的半角、全角和排版连接符。
    private static let rangeSeparators = CharacterSet(charactersIn: "-~～–—")

    static func parse(_ rawValue: String, maximumPageCount: Int) throws -> [Int] {
        guard maximumPageCount > 0 else {
            throw PageRangeError.documentHasNoPages
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(1...maximumPageCount)
        }

        var pages = Set<Int>()
        let items = trimmed.components(separatedBy: CharacterSet(charactersIn: ",，"))

        for rawItem in items {
            let item = rawItem.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else {
                throw PageRangeError.emptyItem
            }

            if item.rangeOfCharacter(from: rangeSeparators) != nil {
                try insertRange(item, maximumPageCount: maximumPageCount, into: &pages)
            } else {
                let page = try parsePage(item, originalItem: item, maximumPageCount: maximumPageCount)
                pages.insert(page)
            }
        }

        guard !pages.isEmpty else {
            throw PageRangeError.invalidItem(trimmed)
        }
        return pages.sorted()
    }

    private static func insertRange(
        _ item: String,
        maximumPageCount: Int,
        into pages: inout Set<Int>
    ) throws {
        let bounds = item.components(separatedBy: rangeSeparators)
        guard bounds.count == 2 else {
            throw PageRangeError.invalidItem(item)
        }

        let startText = bounds[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let endText = bounds[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !startText.isEmpty, !endText.isEmpty else {
            throw PageRangeError.invalidItem(item)
        }

        let start = try parsePage(startText, originalItem: item, maximumPageCount: maximumPageCount)
        let end = try parsePage(endText, originalItem: item, maximumPageCount: maximumPageCount)

        // 兼容用户倒序输入，例如 8-5 会按 5、6、7、8 处理。
        for page in min(start, end)...max(start, end) {
            pages.insert(page)
        }
    }

    private static func parsePage(
        _ value: String,
        originalItem: String,
        maximumPageCount: Int
    ) throws -> Int {
        guard let page = Int(value), page > 0 else {
            throw PageRangeError.invalidItem(originalItem)
        }
        guard page <= maximumPageCount else {
            throw PageRangeError.pageOutOfBounds(page: page, maximum: maximumPageCount)
        }
        return page
    }
}
