import SwiftUI
import PDFKit

// MARK: - 右侧结果展示视图 (PDF 原件预览 与 提取文字 左右并排对照版)
struct ResultView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @ObservedObject var aiEngine: AIProcessingEngine
    
    @Binding var resultText: String
    @Binding var txtFileURL: URL?
    @Binding var mdFileURL: URL?
    
    // selectedTab: 0 -> 原始提取文本, 1 -> 本地 AI 纠错净化
    @Binding var selectedTab: Int
    
    // 复制状态动画控制
    @State private var copiedRaw = false
    @State private var copiedClean = false
    
    // 大文件渲染只读保护限制
    private var previewTextBinding: Binding<String> {
        Binding(
            get: {
                if resultText.count > 15000 {
                    return String(resultText.prefix(15000)) + "\n\n【⚠️ 性能保护提示：文本总长度较大（当前共 \(resultText.count) 字），预览区已为您自动截断并展示前 15,000 字，以确保系统流畅。完整文本内容已自动安全保存在本地 TXT 和 Markdown 文件夹内。】"
                }
                return resultText
            },
            set: { _ in }
        )
    }
    
    private var aiPreviewTextBinding: Binding<String> {
        Binding(
            get: {
                if aiEngine.aiResultText.count > 15000 {
                    return String(aiEngine.aiResultText.prefix(15000)) + "\n\n【⚠️ 性能保护提示：AI 生成结果过长（当前共 \(aiEngine.aiResultText.count) 字），预览区已自动截断前 15,000 字以防渲染卡死。完整净化文本已安全写入本地。】"
                }
                return aiEngine.aiResultText
            },
            set: { _ in }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if engine.isProcessing {
                // 1. 提取中进度环状态
                VStack(spacing: 24) {
                    Spacer()
                    
                    ProgressShimmerRing(progress: engine.progress, etaText: engine.etaString)
                    
                    VStack(spacing: 8) {
                        Text(engine.currentStatus)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("正在调用本地 Vision 图像识别与去水印引擎...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    // 中止提取
                    Button(action: {
                        engine.cancelPDFExtraction()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle")
                            Text("停止任务")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    // 日志输出
                    ScrollView {
                        Text(engine.logOutput)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                            .cornerRadius(6)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: 500) // 解决 P2-4 宽度固定问题，改为最大宽度限制
                    .frame(height: 180)
                    .padding(.top, 10)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if !resultText.isEmpty || engine.pdfDocument != nil {
                // 2. 双栏并排对照展示
                HSplitView {
                    // 左半部分：常驻原件 PDF 预览区 (P1 提取前后对比核心实现)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "eye")
                                .foregroundColor(.secondary)
                            Text("PDF 原始页面对照")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        
                        Divider()
                        
                        if let doc = engine.pdfDocument {
                            PDFPreviewView(pdfDocument: doc)
                                .background(Color(nsColor: .textBackgroundColor))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        } else {
                            VStack {
                                Spacer()
                                Image(systemName: "doc.text")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(0.3))
                                Text("未检测到有效 PDF 原件")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 320, maxWidth: .infinity)
                    
                    // 右半部分：去水印文本展示区
                    VStack(alignment: .leading, spacing: 0) {
                        // 顶部辅助栏：选项切换与复制导出 (苹果 native 分栏顶栏设计)
                        HStack {
                            // 替换原先手绘 Tab 按钮，采用标准 Segmented Picker
                            Picker("", selection: $selectedTab) {
                                Text("原始文本").tag(0)
                                Text("AI 净化").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                            
                            Spacer()
                            
                            // 复制操作 (使用标准 bordered 扁平按键代替彩色卡片)
                            if selectedTab == 0 {
                                Button(action: copyRawAction) {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedRaw ? "checkmark" : "doc.on.doc")
                                        Text(copiedRaw ? "已复制" : "复制")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else if selectedTab == 1 {
                                if !aiEngine.aiResultText.isEmpty {
                                    Button(action: copyCleanAction) {
                                        HStack(spacing: 4) {
                                            Image(systemName: copiedClean ? "checkmark" : "doc.on.doc")
                                            Text(copiedClean ? "已复制" : "复制")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        
                        Divider()
                        
                        // Finder 文件直达区：替换手绘弹窗卡片，升级为符合 HIG 的扁平式 Accessory Bar
                        if selectedTab == 0 {
                            if let url = txtFileURL, let mdUrl = mdFileURL {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.secondary)
                                    Text("提取成功！导出路径：")
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }) {
                                        Text(url.lastPathComponent)
                                            .underline()
                                    }
                                    .buttonStyle(.link)
                                    .foregroundColor(.accentColor)
                                    
                                    Text("和")
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        NSWorkspace.shared.activateFileViewerSelecting([mdUrl])
                                    }) {
                                        Text(mdUrl.lastPathComponent)
                                            .underline()
                                    }
                                    .buttonStyle(.link)
                                    .foregroundColor(.accentColor)
                                    
                                    Spacer()
                                }
                                .font(.system(size: 11))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 16)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(Color(nsColor: .separatorColor)),
                                    alignment: .bottom
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        } else if selectedTab == 1 {
                            if let url = aiEngine.aiTxtFileURL, let mdUrl = aiEngine.aiMdFileURL {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.purple)
                                    Text("AI 净化完毕！导出路径：")
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }) {
                                        Text(url.lastPathComponent)
                                            .underline()
                                    }
                                    .buttonStyle(.link)
                                    .foregroundColor(.purple)
                                    
                                    Text("和")
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        NSWorkspace.shared.activateFileViewerSelecting([mdUrl])
                                    }) {
                                        Text(mdUrl.lastPathComponent)
                                            .underline()
                                    }
                                    .buttonStyle(.link)
                                    .foregroundColor(.purple)
                                    
                                    Spacer()
                                }
                                .font(.system(size: 11))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 16)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(Color(nsColor: .separatorColor)),
                                    alignment: .bottom
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        
                        // 文本展示区域，使用自制的只读 ReadOnlyTextView (P1-6 修复)
                        if selectedTab == 0 {
                            ReadOnlyTextView(text: previewTextBinding.wrappedValue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        } else {
                            // AI 净化文本
                            if !aiEngine.aiResultText.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    // 顶层流式推理进度显示条，扁平嵌入，不遮挡
                                    if aiEngine.isAIProcessing {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                                .scaleEffect(0.6)
                                            
                                            Text("⚡️ AI 正在处理：第 \(aiEngine.aiCurrentChunkIndex + 1) / \(aiEngine.aiTotalChunks) 段 (已完成 \(aiEngine.aiCurrentChunkIndex) 段)...")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.purple)
                                            
                                            Spacer()
                                        }
                                        .padding(.vertical, 5)
                                        .padding(.horizontal, 16)
                                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                                        .transition(.opacity)
                                    }
                                    
                                    ReadOnlyTextView(text: aiPreviewTextBinding.wrappedValue)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                }
                            } else if aiEngine.isAIProcessing {
                                // 初始化加载状态
                                VStack(spacing: 16) {
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.regular)
                                    
                                    VStack(spacing: 6) {
                                        Text("正在连接本地模型...")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(aiEngine.aiProgressStatus)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 40)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                // 空白 AI 引导页，使用优雅的主题色渐变点缀
                                VStack(spacing: 12) {
                                    Spacer()
                                    
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 36))
                                        .foregroundColor(.purple.opacity(0.8))
                                    
                                    Text("本地 AI 文本排版与纠错")
                                        .font(.system(size: 14, weight: .bold))
                                    
                                    Text("本地 AI 可以修复 OCR 扫描识别产生的错别字，并根据上下文智能合并生硬的句末截断换行。\n所有的排版和字词修改都会用【大括号】在旁边标出，以供核实。")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(4.5)
                                        .padding(.horizontal, 60)
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                    .frame(minWidth: 420, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 3. 空白欢迎状态
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 56))
                        .foregroundColor(.secondary.opacity(0.25))
                    
                    Text("暂无提取内容")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text("请在顶部工具栏导入 PDF，并在左侧面板中配置去水印词库")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func copyRawAction() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resultText, forType: .string)
        withAnimation {
            copiedRaw = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                copiedRaw = false
            }
        }
    }
    
    private func copyCleanAction() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(aiEngine.aiResultText, forType: .string)
        withAnimation {
            copiedClean = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                copiedClean = false
            }
        }
    }
}
