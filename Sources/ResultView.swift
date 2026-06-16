import SwiftUI
import PDFKit

// MARK: - 右侧结果展示视图 (PDF 原件预览、提取文字与 AI 净化 Tab 页模式)
struct ResultView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @ObservedObject var aiEngine: AIProcessingEngine
    
    @Binding var resultText: String
    @Binding var txtFileURL: URL?
    @Binding var mdFileURL: URL?
    
    // selectedTab: 0 -> PDF 原件, 1 -> 原始提取文本, 2 -> 本地 AI 纠错净化
    @Binding var selectedTab: Int
    
    // 复制状态动画控制
    @State private var copiedRaw = false
    @State private var copiedClean = false
    
    // 大文件渲染只读保护限制 (解决性能瓶颈，防止 UI 主线程卡死)
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
                // ==================== 1. 提取中进度环状态 ====================
                VStack(spacing: Theme.Spacing.xl) {
                    Spacer()
                    
                    ProgressShimmerRing(progress: engine.progress, etaText: engine.etaString)
                    
                    VStack(spacing: Theme.Spacing.sm) {
                        Text(engine.currentStatus)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("正在调用本地 Vision 图像识别与去水印引擎...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    // 中止提取按钮
                    Button(action: {
                        engine.cancelPDFExtraction()
                    }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "stop.circle")
                            Text("停止任务")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    // 日志流输出
                    ScrollView {
                        Text(engine.logOutput)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.md)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                            .cornerRadius(6)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: 500)
                    .frame(height: 180)
                    .padding(.top, Theme.Spacing.sm)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity) // 加入状态淡入淡出动画过渡
                
            } else if !resultText.isEmpty || engine.pdfDocument != nil {
                // ==================== 2. 已导入或提取完毕展示区 ====================
                VStack(spacing: 0) {
                    // 顶部控制导航栏 (包含 Tab 切换和复制)
                    HStack {
                        // 优化 1: 弃用内部嵌套 HSplitView。统一使用 Tab 切换 (PDF原件, 提取文本, AI净化)
                        Picker("", selection: $selectedTab) {
                            Text("PDF 原件").tag(0)
                            Text("提取文本").tag(1)
                            Text("AI 净化").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                        
                        Spacer()
                        
                        // 复制与导出控制按钮
                        if selectedTab == 1 {
                            Button(action: copyRawAction) {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: copiedRaw ? "checkmark" : "doc.on.doc")
                                    Text(copiedRaw ? "已复制" : "复制")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if selectedTab == 2 {
                            if !aiEngine.aiResultText.isEmpty {
                                Button(action: copyCleanAction) {
                                    HStack(spacing: Theme.Spacing.xs) {
                                        Image(systemName: copiedClean ? "checkmark" : "doc.on.doc")
                                        Text(copiedClean ? "已复制" : "复制")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
                    
                    Divider()
                    
                    // 根据当前选中的 Tab 进行视图独占排版展示
                    if selectedTab == 0 {
                        // PDF 原始页面对照
                        VStack(alignment: .leading, spacing: 0) {
                            if let doc = engine.pdfDocument {
                                PDFPreviewView(pdfDocument: doc)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .padding(.horizontal, Theme.Spacing.lg)
                                    .padding(.vertical, Theme.Spacing.md)
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
                        .transition(.opacity)
                        
                    } else if selectedTab == 1 {
                        // 提取文本 Tab
                        VStack(alignment: .leading, spacing: 0) {
                            // 挂载公共导出的 Accessory Bar
                            if let url = txtFileURL, let mdUrl = mdFileURL {
                                AccessoryBarView(
                                    iconName: "info.circle",
                                    title: "提取成功！导出路径：",
                                    themeColor: .accentColor,
                                    txtFileURL: url,
                                    mdFileURL: mdUrl
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            
                            // 文本展示容器 (只读 NSTextView)
                            ReadOnlyTextView(text: previewTextBinding.wrappedValue)
                                .padding(.horizontal, Theme.Spacing.lg)
                                .padding(.vertical, Theme.Spacing.md)
                        }
                        .transition(.opacity)
                        
                    } else if selectedTab == 2 {
                        // AI 净化 Tab
                        VStack(alignment: .leading, spacing: 0) {
                            if !aiEngine.aiResultText.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    // 挂载 AI 专属紫色的导出 Accessory Bar
                                    if let url = aiEngine.aiTxtFileURL, let mdUrl = aiEngine.aiMdFileURL {
                                        AccessoryBarView(
                                            iconName: "sparkles",
                                            title: "AI 净化完毕！导出路径：",
                                            themeColor: .purple,
                                            txtFileURL: url,
                                            mdFileURL: mdUrl
                                        )
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                    
                                    // 顶层流式推理进度显示条，扁平嵌入
                                    if aiEngine.isAIProcessing {
                                        HStack(spacing: Theme.Spacing.sm) {
                                            ProgressView()
                                                .controlSize(.small)
                                                .scaleEffect(0.6)
                                            
                                            Text("⚡️ AI 正在处理：第 \(aiEngine.aiCurrentChunkIndex + 1) / \(aiEngine.aiTotalChunks) 段 (已完成 \(aiEngine.aiCurrentChunkIndex) 段)...")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.purple)
                                            
                                            Spacer()
                                        }
                                        .padding(.vertical, Theme.Spacing.xs)
                                        .padding(.horizontal, Theme.Spacing.lg)
                                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                                        .transition(.opacity)
                                    }
                                    
                                    ReadOnlyTextView(text: aiPreviewTextBinding.wrappedValue)
                                        .padding(.horizontal, Theme.Spacing.lg)
                                        .padding(.vertical, Theme.Spacing.md)
                                }
                            } else if aiEngine.isAIProcessing {
                                // 初始化连接模型时的等待状态
                                VStack(spacing: Theme.Spacing.lg) {
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
                                            .padding(.horizontal, Theme.Spacing.xxl)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                // 升级为极具科技感的 Liquid Glass (液态玻璃) 风格 AI 引导页
                                LiquidGlassContainer {
                                    VStack(spacing: Theme.Spacing.lg) {
                                        // 拟物化玻璃水滴图标底座 (AI 专属紫色)
                                        LiquidGlassIconBase(iconName: "sparkles", usePurpleTheme: true)
                                            .padding(.bottom, Theme.Spacing.md)
                                        
                                        Text("本地 AI 文本排版与纠错")
                                            .font(.system(.title3, design: .rounded).weight(.bold))
                                            .foregroundColor(.primary)
                                        
                                        Text("本地 AI 可以修复 OCR 扫描识别产生的错别字，并根据上下文智能合并生硬的句末截断换行。\n所有的排版和字词修改都会用【大括号】在旁边标出，以供核实。")
                                            .font(.system(.footnote))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .lineSpacing(5)
                                            .frame(maxWidth: 420)
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                
            } else {
                // ==================== 3. 升级为 Liquid Glass 风格的空白欢迎状态 ====================
                LiquidGlassContainer {
                    VStack(spacing: Theme.Spacing.lg) {
                        // 拟物化玻璃水滴图标底座 (常规提取使用系统强调色)
                        LiquidGlassIconBase(iconName: "doc.text", usePurpleTheme: false)
                            .padding(.bottom, Theme.Spacing.md)
                        
                        Text("暂无提取内容")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.primary)
                        
                        Text("请在顶部工具栏导入 PDF，并在左侧控制面板进行分析提取。\n系统将自动剔除高频疑似水印，并为您自动导出 TXT 和精美排版的 Markdown 文件。")
                            .font(.system(.footnote))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .frame(maxWidth: 400)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        // 挂载 state 过渡动画
        .animation(.easeInOut(duration: 0.25), value: engine.isProcessing)
        .animation(.easeInOut(duration: 0.25), value: resultText.isEmpty)
        .animation(.easeInOut(duration: 0.25), value: selectedTab)
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
