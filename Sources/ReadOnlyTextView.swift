import SwiftUI

// MARK: - 只读文本展示视图 (NSTextView 包装)
// 支持文本选中和复制，但禁止编辑，避免 TextEditor 带来的可编辑误导。
// 具备“智能吸底滚动”机制，流式输出时只有用户处于底部才自动滚屏，绝不劫持用户向上翻阅的手势。
struct ReadOnlyTextView: NSViewRepresentable {
    let text: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            textView.textColor = NSColor.textColor
            textView.backgroundColor = NSColor.textBackgroundColor
            textView.textContainerInset = NSSize(width: 10, height: 10)
            
            // 关闭自动文本替换，防止干扰原文展示
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            
            // 关键排版设置：启用纵向自适应并禁止横向自适应，让排版强制触发自动折行
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            
            // 绑定 TextContainer 的宽度自适应，使其充满 ScrollView 并实时追踪宽度变动
            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            }
        }
        
        // 监听滚动条位置，判断用户当前是否在底部
        let contentView = scrollView.contentView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleBoundsChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
        
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
                        
                        // 智能吸底：只有当用户正在最底部时才跟随流式滚动，防止打扰用户向上翻阅
                        if context.coordinator.isUserNearBottom {
                            textView.scrollRangeToVisible(NSRange(location: textStorage.length, length: 0))
                        }
                    }
                } else {
                    // 否则执行全量更新（如切换文档或翻页），并重置到底部跟踪状态
                    textView.string = text
                    context.coordinator.isUserNearBottom = true
                }
            }
        }
    }
    
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: NSView.boundsDidChangeNotification,
            object: nsView.contentView
        )
    }
    
    // MARK: - 滚动位置监听协调器
    class Coordinator: NSObject {
        var isUserNearBottom = true
        
        @MainActor
        @objc func handleBoundsChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let documentView = clipView.documentView else { return }
            
            let visibleRect = clipView.documentVisibleRect
            let totalHeight = documentView.bounds.height
            let currentBottom = visibleRect.origin.y + visibleRect.size.height
            
            // 允许 36pt 缓冲区，判定用户当前是否处于文档底部
            isUserNearBottom = (totalHeight - currentBottom) <= 36
        }
    }
}

#if canImport(PreviewsMacros)
#Preview {
    ReadOnlyTextView(
        text: "第 1 页\n\n这里显示提取后的只读文本，支持选择与复制，具备智能吸底滚动机制。"
    )
    .frame(width: 420, height: 320)
}
#endif
