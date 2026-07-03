import SwiftUI

// MARK: - 只读文本展示视图 (NSTextView 包装)
// 支持文本选中和复制，但禁止编辑，避免 TextEditor 带来的可编辑误导。
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
            
            // 关键修复：启用纵向自适应并禁止横向自适应，让排版强制触发自动折行 (解决行尾大空白)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            
            // 绑定 TextContainer 的宽度自适应，使其充满 ScrollView 并实时追踪 TextView 宽度变动
            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            }
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
