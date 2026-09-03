import Foundation

// MARK: - AI 提示词构建器
/// 集中管理默认提示词与可选附加指令，避免多个视图各自拼接同一套 AI 规则。
enum AIPromptBuilder {
    static let defaultSystemPrompt = """
    你是一个严谨的文本排版、错别字纠正与 Markdown 转换助手。你将接收一段由 OCR 引擎从 PDF 中识别出的原始文本。
    请执行以下处理：
    1. 保持原文主体段落结构与逻辑含义不变，不重写、不缩写、不扩写正文内容。
    2. 修复 OCR 识别误差导致的明显错字、别字，例如将“面且”纠正为“而且”。
    3. 合并 OCR 扫描造成的生硬断行，同时保留原文自然段落。
    4. 将明显标题、章节、列表转换为规范 Markdown 标记。
    5. 只输出处理后的正文，不输出开场白、总结语或 Markdown 代码块围栏。
    """
    
    private static let changeTrackingInstruction = """
    
    【修改留痕指令】
    每当你修正错别字时，请直接将修正后的正确字词用 Markdown 粗体（如 **修正词**）包裹呈现，便于用户快速比对；保持段落行文自然流畅，不要输出多余的解释性括号。
    """
    
    /// 读取用户保存的系统提示词。若用户从未保存过，则返回工程内唯一默认值。
    static func storedSystemPrompt() -> String {
        if let storedPrompt = UserDefaults.standard.string(forKey: "systemPrompt")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !storedPrompt.isEmpty {
            return storedPrompt
        }
        return defaultSystemPrompt
    }
    
    /// 组合最终发送给本地 AI 端点的系统提示词。
    static func composedPrompt(
        basePrompt: String,
        showChanges: Bool,
        passWatermarks: Bool,
        activeWatermarks: Set<String>,
        customWatermarks: String
    ) -> String {
        var finalPrompt = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if showChanges {
            finalPrompt += changeTrackingInstruction
        }
        
        if passWatermarks {
            let allWatermarks = activeWatermarks.union(parsedWatermarks(from: customWatermarks))
            if !allWatermarks.isEmpty {
                let watermarkText = allWatermarks.sorted().joined(separator: ", ")
                finalPrompt += """
                
                【已知水印残留词】
                \(watermarkText)
                如果输入正文中出现这些词造成的无意义残留、乱码或碎裂字符，请将其作为噪音过滤；若该词在上下文中属于正常正文含义，则必须保留。
                """
            }
        }
        
        return finalPrompt
    }
    
    /// 将逗号、中文逗号或换行分隔的自定义水印词整理成去重集合。
    static func parsedWatermarks(from rawText: String) -> Set<String> {
        WatermarkTermParser.parse(rawText)
    }
}
