import Foundation

// MARK: - 离线智能段落重构引擎 (Heuristic Paragraph Reconstructor)

/// 负责将 PDF 提取或 OCR 识别出的生硬单行碎文本，根据自然语言标点、列表与标题规则，重构为自然流畅的段落。
/// 彻底解决传统 PDF 提取每行末尾带硬回车（\n），导致复制到 Word 或微信时断行破碎的痛点。
public enum ParagraphReconstructor {

    /// 常见段落结束标点符号集合（中文与西文）
    private static let terminalPunctuations: Set<Character> = [
        "。", "！", "？", "…", ".", "!", "?", "；", ";"
    ]

    /// 常见成对闭合标点（如引号、括号），若紧跟在终结标点后仍视为段落结束
    private static let closingQuotes: Set<Character> = [
        "”", "’", "』", "」", "\"", "'", "）", ")", "》", "]", "】"
    ]

    /// 英文常见缩写词集合（行末出现时不作为句子终结，避免误断句）
    private static let abbreviations: Set<String> = [
        "mr.", "mrs.", "ms.", "dr.", "prof.", "sr.", "jr.", "vs.",
        "etc.", "e.g.", "i.e.", "fig.", "no.", "vol.", "dept.",
        "al.", "co.", "inc.", "ltd.", "corp.", "jan.", "feb.",
        "mar.", "apr.", "jun.", "jul.", "aug.", "sep.", "sept.",
        "oct.", "nov.", "dec.", "u.s.", "u.k."
    ]

    /// 重构输入文本，合并段内断行并保持自然段落与结构
    /// - Parameters:
    ///   - rawText: 原始单行碎文本
    /// - Returns: 重构后的段落规整文本
    public static func reconstruct(_ rawText: String) -> String {
        let lines = rawText.components(separatedBy: .newlines)
        let paragraphs = reconstructParagraphs(lines)
        return paragraphs.joined(separator: "\n\n")
    }

    /// 将由多行组成的单行切片文本数组重构为规整的自然段落数组
    /// - Parameter lines: 原始行数组
    /// - Returns: 重构合并后的自然段落数组
    public static func reconstructParagraphs(_ lines: [String]) -> [String] {
        guard !lines.isEmpty else { return [] }

        var paragraphs: [String] = []
        var currentParagraphBuffer: [String] = []

        for line in lines {
            // 检查是否有段首全角空格或制表符缩进（如“　　”）
            let hasParagraphIndentation = line.hasPrefix("\u{3000}") || line.hasPrefix("    ") || line.hasPrefix("\t")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行代表显式的段落切分
            if trimmed.isEmpty {
                if !currentParagraphBuffer.isEmpty {
                    paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
                    currentParagraphBuffer.removeAll(keepingCapacity: true)
                }
                continue
            }

            // 如果当前行具有明确的段首缩进，且已有累积内容，则前面的内容必须封口成段
            if hasParagraphIndentation && !currentParagraphBuffer.isEmpty {
                paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
                currentParagraphBuffer.removeAll(keepingCapacity: true)
            }

            // 如果当前行是独立结构元素（如标题、列表、代码块标记），立即单独分段
            if isStructuralLine(trimmed) {
                if !currentParagraphBuffer.isEmpty {
                    paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
                    currentParagraphBuffer.removeAll(keepingCapacity: true)
                }
                paragraphs.append(trimmed)
                continue
            }

            // 检查上一行是否以终止标点结束；如果是，则上一行形成段落闭环
            if let lastLine = currentParagraphBuffer.last, endsWithTerminalPunctuation(lastLine) {
                paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
                currentParagraphBuffer.removeAll(keepingCapacity: true)
            }

            // 若作为新段落首行且具有段首缩进，保留全角空格或缩进，仅修剪行尾空白
            let lineContent: String
            if currentParagraphBuffer.isEmpty && hasParagraphIndentation {
                lineContent = line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            } else {
                lineContent = trimmed
            }

            currentParagraphBuffer.append(lineContent)
        }

        if !currentParagraphBuffer.isEmpty {
            paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
        }

        return paragraphs
    }

    // MARK: - 辅助判定逻辑

    /// 判定单行是否为结构性行（标题、列表符号、分隔符等）
    public static func isStructuralLine(_ line: String) -> Bool {
        // Markdown 标题
        if line.hasPrefix("#") { return true }

        // Markdown 引用或列表符号
        if line.hasPrefix(">") || line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") || line.hasPrefix("• ") {
            return true
        }

        // 数字或中文序号编号列表，如 "1. ", "12. ", "（一）", "第一章", "第1条", "一、"
        if let firstChar = line.first {
            if firstChar.isNumber {
                if let dotIndex = line.firstIndex(of: ".") ?? line.firstIndex(of: "、") ?? line.firstIndex(of: ")"),
                   line.distance(from: line.startIndex, to: dotIndex) <= 4 {
                    return true
                }
            }
            if line.hasPrefix("（") || line.hasPrefix("(") || line.hasPrefix("【") || line.hasPrefix("[") {
                return true
            }
            if line.hasPrefix("第") && (line.contains("章") || line.contains("节") || line.contains("条") || line.contains("篇") || line.contains("款")) {
                return true
            }
            if ["一、", "二、", "三、", "四、", "五、", "六、", "七、", "八、", "九、", "十、"].contains(where: { line.hasPrefix($0) }) {
                return true
            }
        }

        return false
    }

    /// 检查行尾是否包含终结标点符号（并过滤常见缩写词）
    public static func endsWithTerminalPunctuation(_ line: String) -> Bool {
        guard let lastChar = line.last else { return false }

        // 终结标点直接命中
        if terminalPunctuations.contains(lastChar) {
            // 若为英文句点，检查是否为常见缩写词（如 Fig. 1, e.g.）
            if lastChar == "." {
                let lower = line.lowercased()
                for abbr in abbreviations {
                    if lower.hasSuffix(abbr) {
                        return false
                    }
                }
            }
            return true
        }

        // 如果最后一个字符是闭合引号/括号，检查前一个字符是否为终止标点
        if closingQuotes.contains(lastChar), line.count >= 2 {
            let secondLastIndex = line.index(line.endIndex, offsetBy: -2)
            let secondLastChar = line[secondLastIndex]
            if terminalPunctuations.contains(secondLastChar) {
                if secondLastChar == "." {
                    let prefix = String(line.dropLast(1)).lowercased()
                    for abbr in abbreviations {
                        if prefix.hasSuffix(abbr) {
                            return false
                        }
                    }
                }
                return true
            }
        }

        return false
    }

    /// 将多行拼接为一个完整段落：
    /// - 支持英文断词连字符自动拼合 (De-hyphenation: 如 "compre-" + "hensive" -> "comprehensive")
    /// - 中文字符间无缝合并（不留空格）
    /// - 西文字符间补充单个空格
    public static func joinLinesIntoParagraph(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        if lines.count == 1 { return lines[0] }

        var result = lines[0]
        for i in 1..<lines.count {
            let currentLine = lines[i]
            guard !currentLine.isEmpty else { continue }

            // 1. 英文连字符拆行修复 (De-hyphenation)
            if result.hasSuffix("-"), result.count >= 2 {
                let secondLastIndex = result.index(result.endIndex, offsetBy: -2)
                let secondLastChar = result[secondLastIndex]
                if let firstChar = currentLine.first,
                   secondLastChar.isLetter && firstChar.isLetter {
                    result.removeLast() // 移除末尾连字符 '-'
                    result += currentLine
                    continue
                }
            }

            guard let lastChar = result.last,
                  let firstChar = currentLine.first else {
                result += currentLine
                continue
            }

            // 2. 中文之间无缝拼接（不增加多余空格）
            if isCJKCharacter(lastChar) || isCJKCharacter(firstChar) {
                result += currentLine
            } else {
                // 3. 西文或数字之间补充标准空格
                result += " " + currentLine
            }
        }
        return result
    }

    /// 检查字符是否属于中日韩常用文字与标点符号区间
    public static func isCJKCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value) || // CJK Unified Ideographs
               (0x3400...0x4DBF).contains(value) || // CJK Extension A
               (0x3000...0x303F).contains(value) || // CJK Symbols and Punctuation
               (0xFF00...0xFFEF).contains(value)    // Halfwidth and Fullwidth Forms
    }
}
