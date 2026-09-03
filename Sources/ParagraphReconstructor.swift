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
        "”", "’", "』", "」", "\"", "'", "）", ")", "》", "]"
    ]

    /// 重构输入文本，合并段内断行并保持自然段落与结构
    /// - Parameters:
    ///   - rawText: 原始单行碎文本
    /// - Returns: 重构后的段落规整文本
    public static func reconstruct(_ rawText: String) -> String {
        let lines = rawText.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return "" }

        var paragraphs: [String] = []
        var currentParagraphBuffer: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行代表显式的段落切分
            if trimmed.isEmpty {
                if !currentParagraphBuffer.isEmpty {
                    paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
                    currentParagraphBuffer.removeAll(keepingCapacity: true)
                }
                continue
            }

            // 如果当前行是独立结构元素（如标题、列表、代码块标记），立即单独分段
            if isStructuralLine(trimmed) {
                if !currentParagraphBuffer.isEmpty {
                    paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
                    currentParagraphBuffer.removeAll(keepingCapacity: true)
                }
                currentParagraphBuffer.append(trimmed)
                // 结构行自身即为一个独立段落
                paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
                currentParagraphBuffer.removeAll(keepingCapacity: true)
                continue
            }

            // 检查上一行是否以终止标点结束；如果是，则上一行形成段落闭环
            if let lastLine = currentParagraphBuffer.last, endsWithTerminalPunctuation(lastLine) {
                paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
                currentParagraphBuffer.removeAll(keepingCapacity: true)
            }

            currentParagraphBuffer.append(trimmed)
        }

        if !currentParagraphBuffer.isEmpty {
            paragraphs.append(joinLinesIntoParagraph(currentParagraphBuffer))
        }

        return paragraphs.joined(separator: "\n\n")
    }

    // MARK: - 辅助判定逻辑

    /// 判定单行是否为结构性行（标题、列表符号、分隔符等）
    private static func isStructuralLine(_ line: String) -> Bool {
        // Markdown 标题
        if line.hasPrefix("#") { return true }

        // Markdown 引用或列表
        if line.hasPrefix(">") || line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return true
        }

        // 数字编号列表，如 "1. ", "12. ", "（一）", "第一章", "第1条"
        if let firstChar = line.first {
            if firstChar.isNumber {
                if let dotIndex = line.firstIndex(of: ".") ?? line.firstIndex(of: "、"),
                   line.distance(from: line.startIndex, to: dotIndex) <= 4 {
                    return true
                }
            }
            if line.hasPrefix("（") || line.hasPrefix("(") || line.hasPrefix("【") {
                return true
            }
            if line.hasPrefix("第") && (line.contains("章") || line.contains("节") || line.contains("条") || line.contains("篇")) {
                return true
            }
        }

        return false
    }

    /// 检查行尾是否包含终结标点符号
    private static func endsWithTerminalPunctuation(_ line: String) -> Bool {
        guard let lastChar = line.last else { return false }

        if terminalPunctuations.contains(lastChar) {
            return true
        }

        // 如果最后一个字符是闭合引号/括号，检查前一个字符是否为终止标点
        if closingQuotes.contains(lastChar), line.count >= 2 {
            let secondLastIndex = line.index(line.endIndex, offsetBy: -2)
            let secondLastChar = line[secondLastIndex]
            return terminalPunctuations.contains(secondLastChar)
        }

        return false
    }

    /// 将多行拼接为一个完整段落：中文字符直接拼合，西文字符用空格连接
    private static func joinLinesIntoParagraph(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        if lines.count == 1 { return lines[0] }

        var result = lines[0]
        for i in 1..<lines.count {
            let previousLine = lines[i - 1]
            let currentLine = lines[i]

            guard let lastChar = previousLine.last,
                  let firstChar = currentLine.first else {
                result += currentLine
                continue
            }

            // 中文之间无需空格拼接
            if isCJKCharacter(lastChar) || isCJKCharacter(firstChar) {
                result += currentLine
            } else {
                // 西文字符间补充一个空格
                result += " " + currentLine
            }
        }
        return result
    }

    /// 检查字符是否属于中日韩常用文字区间
    private static func isCJKCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value) || // CJK Unified Ideographs
               (0x3400...0x4DBF).contains(value) || // CJK Extension A
               (0x3000...0x303F).contains(value) || // CJK Symbols and Punctuation
               (0xFF00...0xFFEF).contains(value)    // Halfwidth and Fullwidth Forms
    }
}
