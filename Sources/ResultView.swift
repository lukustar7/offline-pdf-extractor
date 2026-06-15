import SwiftUI
import PDFKit

// MARK: - 右侧结果展示视图 (支持 PDF 预览 / 提取文本 / AI 纠错净化)
struct ResultView: View {
    @ObservedObject var engine: PDFExtractorEngine
    @ObservedObject var aiEngine: AIProcessingEngine
    
    @Binding var resultText: String
    @Binding var txtFileURL: URL?
    @Binding var selectedTab: Int
    
    // 复制状态控制
    @State private var copiedRaw = false
    @State private var copiedClean = false
    
    // 大文件渲染保护限制
    private var previewTextBinding: Binding<String> {
        Binding(
            get: {
                if resultText.count > 15000 {
                    return String(resultText.prefix(15000)) + "\n\n【⚠️ 性能保护提示：文本总长度较大（当前共 \(resultText.count) 字），预览区已为您自动截断并展示前 15,000 字，以确保系统流畅。完整文本内容已自动安全保存在本地 TXT 文件夹内。】"
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("正在使用 Vision 本地引擎，请勿关闭应用")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    // 中止提取
                    Button(action: {
                        engine.cancelPDFExtraction()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle")
                            Text("取消提取")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // 日志输出
                    ScrollView {
                        Text(engine.logOutput)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                            .lineSpacing(4)
                    }
                    .frame(width: 500, height: 180)
                    .padding(.top, 10)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if !resultText.isEmpty || engine.pdfDocument != nil {
                // 2. 正常展示状态卡片 (三 Tab 切换)
                VStack(alignment: .leading, spacing: 0) {
                    
                    // 顶部精美 TabBar 与快捷复制
                    HStack {
                        HStack(spacing: 4) {
                            Button(action: { selectedTab = 0 }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye")
                                    Text("PDF 预览")
                                }
                                .font(.system(size: 12.5, weight: selectedTab == 0 ? .bold : .medium))
                                .padding(.vertical, 7)
                                .padding(.horizontal, 14)
                                .background(selectedTab == 0 ? Color.blue.opacity(0.15) : Color.clear)
                                .foregroundColor(selectedTab == 0 ? .blue : .primary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { selectedTab = 1 }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.text")
                                    Text("原始提取文本")
                                }
                                .font(.system(size: 12.5, weight: selectedTab == 1 ? .bold : .medium))
                                .padding(.vertical, 7)
                                .padding(.horizontal, 14)
                                .background(selectedTab == 1 ? Color.blue.opacity(0.15) : Color.clear)
                                .foregroundColor(selectedTab == 1 ? .blue : .primary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { selectedTab = 2 }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                    Text("本地 AI 纠错净化")
                                }
                                .font(.system(size: 12.5, weight: selectedTab == 2 ? .bold : .medium))
                                .padding(.vertical, 7)
                                .padding(.horizontal, 14)
                                .background(selectedTab == 2 ? Color.purple.opacity(0.15) : Color.clear)
                                .foregroundColor(selectedTab == 2 ? .purple : .primary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(3)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        // 复制操作与反馈动画
                        HStack(spacing: 10) {
                            if selectedTab == 1 {
                                Button(action: copyRawAction) {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedRaw ? "checkmark.circle.fill" : "doc.on.doc")
                                        Text(copiedRaw ? "已复制 ✓" : "复制原始")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(copiedRaw ? Color.green.opacity(0.15) : Color.blue.opacity(0.1))
                                    .foregroundColor(copiedRaw ? .green : .blue)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            } else if selectedTab == 2 {
                                if !aiEngine.aiResultText.isEmpty {
                                    Button(action: copyCleanAction) {
                                        HStack(spacing: 4) {
                                            Image(systemName: copiedClean ? "checkmark.circle.fill" : "doc.on.doc")
                                            Text(copiedClean ? "已复制 ✓" : "复制净化文本")
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(copiedClean ? Color.green.opacity(0.15) : Color.purple.opacity(0.15))
                                        .foregroundColor(copiedClean ? .green : .purple)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // Finder 直达 Banner
                    if selectedTab == 1 {
                        if let url = txtFileURL {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 13, weight: .bold))
                                Text("🎉 文字提取已完成！已自动导出原始文本至: ")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.primary)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(.green)
                                    .underline()
                                    .onTapGesture {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                    .help("点击在 Finder 中定位该文件")
                                Spacer()
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 14)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green.opacity(0.25), lineWidth: 1)
                            )
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    } else if selectedTab == 2 {
                        if let url = aiEngine.aiTxtFileURL {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.purple)
                                    .font(.system(size: 13, weight: .bold))
                                Text("✨ AI 优化已完成！已自动导出净化文本至: ")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.primary)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(.purple)
                                    .underline()
                                    .onTapGesture {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                    .help("点击在 Finder 中定位该文件")
                                Spacer()
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 14)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                            )
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    
                    // Tab 内容区
                    if selectedTab == 0 {
                        // PDF 预览 Tab (P0)
                        if let doc = engine.pdfDocument {
                            PDFPreviewView(pdfDocument: doc)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(8)
                                .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 20)
                        } else {
                            VStack {
                                Spacer()
                                Text("无法渲染预览，文档加载失败。")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else if selectedTab == 1 {
                        // 原始文本展示 (只读以作安全预览)
                        TextEditor(text: previewTextBinding)
                            .font(.system(.body, design: .default))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                        
                    } else {
                        // AI 优化展示
                        if !aiEngine.aiResultText.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                // 推理中流光提示
                                if aiEngine.isAIProcessing {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .scaleEffect(0.7)
                                        
                                        Text("⚡️ AI 正在接力流式净化中：第 \(aiEngine.aiCurrentChunkIndex + 1) / \(aiEngine.aiTotalChunks) 段 (已完成并自动落盘 \(aiEngine.aiCurrentChunkIndex) 段)...")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundColor(.purple)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            aiEngine.cancelAIProcessing()
                                        }) {
                                            Text("取消优化")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.red)
                                                .underline()
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 9)
                                    .padding(.horizontal, 14)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                                    )
                                    .padding(.horizontal, 24)
                                    .padding(.top, 14)
                                    .transition(.opacity)
                                }
                                
                                TextEditor(text: aiPreviewTextBinding)
                                    .font(.system(.body, design: .default))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(8)
                                    .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 20)
                            }
                        } else if aiEngine.isAIProcessing {
                            // 等待载入模型状态
                            VStack(spacing: 24) {
                                Spacer()
                                ProgressView()
                                    .controlSize(.large)
                                
                                VStack(spacing: 8) {
                                    Text("正在连接本地模型并初始化首段...")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(aiEngine.aiProgressStatus)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                                
                                Button(action: {
                                    aiEngine.cancelAIProcessing()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle")
                                        Text("取消优化")
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // 未开始净化引导
                            VStack(spacing: 16) {
                                Spacer()
                                
                                Image(systemName: "sparkles")
                                    .font(.system(size: 48))
                                    .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                                
                                Text("本地 AI 文本净化")
                                    .font(.system(size: 15, weight: .bold))
                                
                                Text("本地 AI 可以智能修复 OCR 扫描产生的错别字，并合并因为换行生硬造成的生硬断行。\n所有的修改都会使用【大括号对】标出，确保可读可查。")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                                    .padding(.horizontal, 50)
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 3. 空白欢迎状态
                VStack(spacing: 18) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                    
                    Text("暂无处理内容")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text("请在左侧导入 PDF 文件并完成水印配置")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
