import SwiftUI

// MARK: - 中部原始识字区组件
/// 展示当前 PDF 物理页提取的原文文本，内置页码翻页控制器以及文本导出。
struct RawTextColumn: View {
    @ObservedObject var engine: PDFExtractorEngine
    @Binding var currentPage: Int
    
    /// 触发提取动作的回调闭包，由 ContentView 传入
    var onStartExtraction: () -> Void
    
    // 鼠标悬停动画状态
    @State private var isHoveredStart = false
    @State private var isHoveredExport = false
    @State private var isHoveredCancel = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶栏大标题区
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.accentColor)
                Text("原始识字区")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                if engine.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
            
            Divider()
            
            // 核心展示区：根据处理状态切换
            ZStack {
                if engine.isProcessing && engine.extractedPagesText.isEmpty {
                    // 当正在提取且没有任何一页提取出来时，展示大进度圆环
                    VStack(spacing: Theme.Spacing.xl) {
                        ProgressShimmerRing(progress: engine.progress, etaText: engine.etaString)
                        
                        Text(engine.currentStatus)
                            .font(.system(.callout))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if engine.extractedPagesText.isEmpty {
                    // 空白未加载/未识别态：高透明液态玻璃卡片
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text("等待提取文本")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(.secondary)
                        
                        Text("请在下方点击“提取文字”开始识别")
                            .font(.system(.caption))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 呈现当前物理页文本
                    let currentPageText = engine.extractedPagesText[currentPage] ?? "（该页文本为空或尚未处理）"
                    
                    ReadOnlyTextView(text: currentPageText)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // 底部操作与页码翻页联动栏
            VStack(spacing: Theme.Spacing.md) {
                if engine.pdfTotalPages > 0 {
                    // 自适应分页控制器
                    HStack(spacing: Theme.Spacing.lg) {
                        Button(action: {
                            if currentPage > 1 {
                                currentPage -= 1
                            }
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(currentPage <= 1 || engine.isProcessing)
                        
                        Text("第 \(currentPage) / \(engine.pdfTotalPages) 页")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .frame(minWidth: 90)
                        
                        Button(action: {
                            if currentPage < engine.pdfTotalPages {
                                currentPage += 1
                            }
                        }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(currentPage >= engine.pdfTotalPages || engine.isProcessing)
                    }
                }
                
                // 操作与导出按钮（与 AI 优化区做镜像对称设计）
                if engine.isProcessing {
                    // 提取中，显示停止按钮和进度
                    HStack {
                        Text(engine.currentStatus)
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(action: {
                            engine.cancelPDFExtraction()
                        }) {
                            Text("停止提取")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                        .scaleEffect(isHoveredCancel ? 1.03 : 1.0)
                        .onHover { h in isHoveredCancel = h }
                    }
                } else {
                    // 闲置时，动作与导出并排
                    HStack(spacing: Theme.Spacing.md) {
                        Button(action: {
                            onStartExtraction()
                        }) {
                            Label("提取文字", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(engine.pdfFileName.isEmpty)
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(engine.pdfFileName.isEmpty ? Color.accentColor.opacity(0.1) : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .scaleEffect(isHoveredStart ? 1.02 : 1.0)
                        .onHover { h in isHoveredStart = h }
                        
                        Button(action: {
                            exportText()
                        }) {
                            Label("导出 TXT", systemImage: "doc.text")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(engine.extractedPagesText.isEmpty)
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                        .scaleEffect(isHoveredExport ? 1.02 : 1.0)
                        .onHover { h in isHoveredExport = h }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
    
    /// 执行系统 NSSavePanel 另存为导出纯文本（物理提取不包含 Markdown，已移除 Markdown 导出）
    private func exportText() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = (engine.pdfFileName as NSString).deletingPathExtension + ".txt"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let sortedPages = engine.extractedPagesText.keys.sorted()
                var content = ""
                
                for page in sortedPages {
                    if let text = engine.extractedPagesText[page] {
                        content += "[第 \(page) 页]\n\(text)\n\n"
                    }
                }
                
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("导出纯文本失败: \(error.localizedDescription)")
                }
            }
        }
    }
}
