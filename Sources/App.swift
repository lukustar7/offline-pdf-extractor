import SwiftUI

// MARK: - App 入口
@main
struct PDFExtractorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .commands {
            // 禁用 Command+N 新建窗口，防止多窗口竞争导致的本地临时文件写入冲突 (P1-8 修复)
            CommandGroup(replacing: .newItem) {}
        }
    }
}
