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
            // 1. 禁用 Command+N 新建窗口，防止多窗口竞争导致的本地临时文件写入冲突 (P1-8 修复)
            CommandGroup(replacing: .newItem) {}
            
            // 2. 核心差距 A 修复：注入系统菜单栏“文件”下的“导入 PDF 文件...”菜单项，并绑定 ⌘O 快捷键
            CommandGroup(after: .importExport) {
                Button("导入 PDF 文件...") {
                    // 发送系统级通知，由主视图捕获并执行导入动作
                    NotificationCenter.default.post(name: NSNotification.Name("OpenFileNotification"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            // 3. 核心差距 A 修复：新建系统级“控制”主菜单，容纳“开始文字提取”(⌘R) 和 “AI 净化排版” 指令
            CommandMenu("控制") {
                Button("开始文字提取") {
                    // 发送提取文字通知
                    NotificationCenter.default.post(name: NSNotification.Name("StartExtractionNotification"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Button("AI 净化排版") {
                    // 发送 AI 净化通知
                    NotificationCenter.default.post(name: NSNotification.Name("StartAINotification"), object: nil)
                }
            }
        }
    }
}
