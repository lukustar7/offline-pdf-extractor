import SwiftUI
import AppKit

// MARK: - App 委托 (负责窗口生命周期与 Dock 点击重新唤醒)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                Self.mainWindow = window
                window.delegate = self
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = Self.mainWindow {
                window.makeKeyAndOrderFront(nil)
                sender.activate(ignoringOtherApps: true)
                return true
            }
            for window in sender.windows where window.canBecomeMain {
                Self.mainWindow = window
                window.delegate = self
                window.makeKeyAndOrderFront(nil)
                sender.activate(ignoringOtherApps: true)
                return true
            }
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === Self.mainWindow {
            sender.orderOut(nil)
            return false
        }
        return true
    }
}

// MARK: - App 入口
@main
struct PDFExtractorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .commands {
            // 1. 禁用 Command+N 新建窗口，防止多窗口并发操作同一份内存状态。
            CommandGroup(replacing: .newItem) {}
            
            // 2. 注入系统菜单栏“文件”下的“导入 PDF 文件...”菜单项，并绑定 ⌘O 快捷键。
            CommandGroup(after: .importExport) {
                Button("导入 PDF 文件...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenFileNotification"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            // 3. 新建系统级“控制”主菜单，容纳“开始文字提取”(⌘R)。
            CommandMenu("控制") {
                Button("开始文字提取") {
                    NotificationCenter.default.post(name: NSNotification.Name("StartExtractionNotification"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            
            // 4. 在“帮助”菜单下注入“欢迎使用 PDF 文字提取”入口，便于随时调出开屏介绍。
            CommandGroup(replacing: .help) {
                Button("欢迎使用 PDF 文字提取") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowWelcomeSheetNotification"), object: nil)
                }
            }
        }
        
        // 5. 挂载标准 macOS 偏好设置窗口 (⌘,)
        Settings {
            SettingsView()
        }
    }
}
