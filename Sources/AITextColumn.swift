import SwiftUI

// MARK: - 右侧 AI 优化净化区组件
/// 展示当前 PDF 物理页 AI 优化净化后的文本，内置 AI 净化启动按钮与 Markdown/TXT 导出。
struct AITextColumn: View {
    @ObservedObject var aiEngine: AIProcessingEngine
    @ObservedObject var extractorEngine: PDFExtractorEngine
    @Binding var currentPage: Int
    
    @AppStorage("systemPrompt") private var systemPrompt = """
    你是一个极为严谨的文本排版、错别字纠正与 Markdown 转换助手。你将接收一段由 OCR 引擎从扫描件中识别出的原始文本。
    请执行以下处理：
    1. 保持原文的主体段落结构与逻辑含义完全不变，切勿重写、缩写或扩写正文内容。
    2. 修复文本中由于 OCR 识别误差导致的可能错字、别字（例如把“而且”识别为“面且”，把“我们”识别为“我门”）。
    3. 智能修复不合理的强行换行：只合并由于 OCR 扫描在行尾造成的生硬硬断行，必须严格保留原文中所有的自然段落结构。
    4. 【Markdown 格式化】：智能分析文本中的标题、段落层级。对于明显的章节标题、小标题、列表项等，在输出中将其规范化转换为 Markdown 标记格式（如章节大标题前加 # 或 ##，列表项前加 - 等），以提高排版可读性。
    5. 只输出处理纠正且 Markdown 规范化后的最终纯净文本，严禁夹带任何多余的开场白、Markdown 代码块围栏（如 ```markdown）或总结语！
    """
    
    @AppStorage("customWatermarks") private var customWatermarks = ""
    
    // 是否悬停于 AI 优化按钮上
    @State private var isHoveredAll = false
    @State private var isHoveredCurrent = false
    @State private var isHoveredCancel = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶栏大标题区
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI 优化区")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                if aiEngine.isAIProcessing {
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
                if aiEngine.isAIProcessing && (aiEngine.aiPagesText[currentPage] ?? "").isEmpty {
                    // 正在进行 AI 净化，且当前物理页尚未输出时，显示流光加载中
                    VStack(spacing: Theme.Spacing.xl) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        Text(aiEngine.aiProgressStatus)
                            .font(.system(.callout))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if aiEngine.aiPagesText.isEmpty {
                    // 空白态：等待用户启动 AI 优化
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 44))
                            .foregroundColor(.purple.opacity(0.4))
                        
                        Text("等待 AI 净化优化")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(.secondary)
                        
                        Text("请在下方点击按钮启动大模型净化校对")
                            .font(.system(.caption))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 呈现当前物理页的 AI 净化结果
                    let currentPageAIText = aiEngine.aiPagesText[currentPage] ?? "（当前页 AI 优化文本为空）"
                    
                    ReadOnlyTextView(text: currentPageAIText)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // 底部操作与另存为栏
            VStack(spacing: Theme.Spacing.md) {
                if aiEngine.isAIProcessing {
                    // 正在处理时，显示取消按钮和整体进度
                    HStack {
                        Text(aiEngine.aiProgressStatus)
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(action: {
                            aiEngine.cancelAIProcessing()
                        }) {
                            Text("中止净化")
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
                    // 闲置时，提供启动 AI 净化的控制按钮
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.md) {
                            Button(action: {
                                startAIPurification(allPages: true)
                            }) {
                                Label("净化全部页", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(extractorEngine.extractedPagesText.isEmpty)
                            .buttonStyle(.plain)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(extractorEngine.extractedPagesText.isEmpty ? Color.purple.opacity(0.1) : Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .scaleEffect(isHoveredAll ? 1.02 : 1.0)
                            .onHover { h in isHoveredAll = h }
                            
                            Button(action: {
                                startAIPurification(allPages: false)
                            }) {
                                Label("仅净化当前页", systemImage: "sparkles.rectangle.stack")
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(extractorEngine.extractedPagesText.isEmpty)
                            .buttonStyle(.plain)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                            .scaleEffect(isHoveredCurrent ? 1.02 : 1.0)
                            .onHover { h in isHoveredCurrent = h }
                        }
                        
                        if !extractorEngine.extractedPagesText.isEmpty {
                            Text("💡 优化采用“一页一送”分片策略，每次仅请求单页文本，完美适配本地小模型，规避显存截断与记忆衰退。")
                                .font(.system(.caption2))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .padding(.top, 2)
                        }
                    }
                }
                
                // 另存为导出按钮
                HStack(spacing: Theme.Spacing.md) {
                    Button(action: {
                        exportAIText(asMarkdown: false)
                    }) {
                        Label("导出 AI TXT", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(aiEngine.aiPagesText.isEmpty)
                    
                    Button(action: {
                        exportAIText(asMarkdown: true)
                    }) {
                        Label("导出 AI Markdown", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(aiEngine.aiPagesText.isEmpty)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
    
    /// 开始物理页码的 AI 优化处理
    private func startAIPurification(allPages: Bool) {
        let targetPages: [Int]
        if allPages {
            targetPages = Array(1...extractorEngine.pdfTotalPages)
        } else {
            targetPages = [currentPage]
        }
        
        let showChanges = UserDefaults.standard.bool(forKey: "aiShowChanges")
        let passWatermarks = UserDefaults.standard.bool(forKey: "aiPassWatermarks")
        
        var finalPrompt = systemPrompt
        
        if showChanges {
            finalPrompt += "\n\n【极其重要——修改留痕指令】：\n每当你在排版、换行、字词或 Markdown 标记上修改或重构了任何内容，你必须在修改后的内容旁边，紧随其后附上大括号，格式为：“【识别是：[原始错误/硬换行]，修改为：[修改后/合并内容/Markdown标记]】”。"
        }
        
        if passWatermarks {
            // 动态拼装水印过滤词，作为上下文负面词输入以增强大模型对水印残留的鉴别过滤能力
            let activeWatermarks = Set(extractorEngine.watermarkCandidates.filter { $0.isSelected }.map { $0.text })
            let customList = customWatermarks
                .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let allWatermarks = activeWatermarks.union(customList)
            
            if !allWatermarks.isEmpty {
                let watermarkStr = allWatermarks.sorted().joined(separator: ", ")
                finalPrompt += "\n\n【参考提示——已知页面残余干扰词】：\(watermarkStr)\n如果输入正文的段落间或句子中，出现了与这些干扰词相关的无意义残留、乱码或碎裂的字符碎片，请在净化时将其作为噪音滤除；但如果该字词在上下文中属于正常的正文句子组成部分且语义连贯，请务必保留，切勿误伤正文。"
            }
        }
        
        aiEngine.processTextWithAI(
            extractedPages: extractorEngine.extractedPagesText,
            targetPages: targetPages,
            systemPrompt: finalPrompt,
            fileURL: extractorEngine.pdfURL
        )
    }
    
    /// 执行系统 NSSavePanel 另存为导出 AI 全文
    private func exportAIText(asMarkdown: Bool) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = asMarkdown ? [.init(filenameExtension: "md")!] : [.plainText]
        
        let baseName = (extractorEngine.pdfFileName as NSString).deletingPathExtension
        savePanel.nameFieldStringValue = "\(baseName)_AI净化" + (asMarkdown ? ".md" : ".txt")
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let sortedPages = aiEngine.aiPagesText.keys.sorted()
                var content = ""
                
                if asMarkdown {
                    content += "# \(extractorEngine.pdfFileName) AI 净化校对正文\n\n"
                    for page in sortedPages {
                        if let text = aiEngine.aiPagesText[page] {
                            content += "## 第 \(page) 页\n\n\(text)\n\n"
                        }
                    }
                } else {
                    for page in sortedPages {
                        if let text = aiEngine.aiPagesText[page] {
                            content += "[第 \(page) 页]\n\(text)\n\n"
                        }
                    }
                }
                
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("导出失败: \(error.localizedDescription)")
                }
            }
        }
    }
}
