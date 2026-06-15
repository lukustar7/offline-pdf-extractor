import SwiftUI

// MARK: - 只读文本展示视图 (NSTextView 包装)
// 支持文本选中和复制，但禁止编辑，避免 TextEditor 的假编辑困惑 (P1-6 修复)
struct ReadOnlyTextView: NSViewRepresentable {
    let text: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            textView.textColor = NSColor.textColor
            textView.backgroundColor = NSColor.textBackgroundColor
            textView.textContainerInset = NSSize(width: 8, height: 8)
            // 关闭自动文本替换，防止干扰原文展示
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
        }
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            let currentString = textView.string
            if currentString != text {
                // 如果新文本是以当前内容为前缀的追加（典型流式输出），执行高性能增量追加
                if text.hasPrefix(currentString) {
                    let newSuffix = String(text.dropFirst(currentString.count))
                    if let textStorage = textView.textStorage {
                        let attrString = NSAttributedString(string: newSuffix, attributes: [
                            .font: textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                            .foregroundColor: textView.textColor ?? NSColor.textColor
                        ])
                        textStorage.append(attrString)
                        // 智能滚动到最底部，让用户能动态跟随 AI 流式输出进度
                        textView.scrollRangeToVisible(NSRange(location: textStorage.length, length: 0))
                    }
                } else {
                    // 否则执行全量更新（如切换文档或清空）
                    textView.string = text
                }
            }
        }
    }
}
