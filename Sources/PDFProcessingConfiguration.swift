import Foundation

// MARK: - PDF 底层去水印模式

/// 描述 PDF 引擎内部采用的去水印方式。
/// 该类型保留为独立模型，便于日志、测试和后续扩展，不与具体界面绑定。
enum WatermarkRemovalMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "智能诊断匹配（推荐）"
    case modeA = "纯文本过滤（文字版 PDF 专用）"
    case modeB = "物理遮罩 + OCR（正文扫描件 + 文字水印）"
    case modeC = "OCR + 智能过滤（纯扫描件水印）"

    var id: String { rawValue }
}

// MARK: - PDF 底层文字提取模式

/// 描述 PDF 引擎读取文本层或执行 OCR 的方式。
enum ExtractionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case smart = "智能提取（推荐）"
    case textOnly = "仅提取活字（极速）"
    case ocrOnly = "强制全部 OCR（适合扫描件）"

    var id: String { rawValue }
}

// MARK: - 面向用户的 PDF 处理场景

/// 用户只需选择真实文件类型，具体的提取通道和去水印模式由这里统一映射。
/// 这样可以避免界面、引擎和导出逻辑分别维护一套容易漂移的规则。
enum PDFProcessingScenario: String, CaseIterable, Identifiable, Codable, Sendable {
    case electronicTextWithTextWatermark
    case scannedTextWithTextWatermark
    case fullyScanned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "电子文本 + 电子水印"
        case .scannedTextWithTextWatermark:
            return "扫描正文 + 电子水印"
        case .fullyScanned:
            return "全扫描件"
        }
    }

    var subtitle: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "正文和水印都可选中，直接清理文本层。"
        case .scannedTextWithTextWatermark:
            return "正文是图片，水印是后加文本，先 OCR 后过滤。"
        case .fullyScanned:
            return "正文和水印都在图像里，整页 OCR 后过滤残留。"
        }
    }

    var systemImage: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "doc.text"
        case .scannedTextWithTextWatermark:
            return "doc.viewfinder"
        case .fullyScanned:
            return "scanner"
        }
    }

    var extractionMode: ExtractionMode {
        switch self {
        case .electronicTextWithTextWatermark:
            return .textOnly
        case .scannedTextWithTextWatermark, .fullyScanned:
            return .ocrOnly
        }
    }

    var watermarkRemovalMode: WatermarkRemovalMode {
        switch self {
        case .electronicTextWithTextWatermark:
            return .modeA
        case .scannedTextWithTextWatermark:
            return .modeB
        case .fullyScanned:
            return .modeC
        }
    }

    var statusDescription: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "读取 PDF 文本层，删除已确认的电子水印词，不重新 OCR。"
        case .scannedTextWithTextWatermark:
            return "保留原始扫描图像执行 Vision OCR，再按电子水印词过滤残留；必要时才手动开启遮罩。"
        case .fullyScanned:
            return "对整页图像执行 OCR，再按水印词过滤文本；重叠严重时可继续使用 AI 净化。"
        }
    }
}

// MARK: - 单次提取请求

/// 将一次提取所需的所有输入收拢为不可变值，防止任务运行期间被界面设置变化干扰。
struct PDFExtractionRequest: Sendable {
    let scenario: PDFProcessingScenario
    let watermarkFilters: Set<String>
    let ignoreCase: Bool
    let eraseImageWatermark: Bool
    let targetPages: [Int]

    /// 构建请求时立即校验页码，并合并自动识别与手动输入的水印词。
    init(
        scenario: PDFProcessingScenario,
        activeWatermarks: Set<String>,
        customWatermarks: String,
        ignoreCase: Bool,
        eraseImageWatermark: Bool,
        pageRangeString: String,
        maximumPageCount: Int
    ) throws {
        self.scenario = scenario
        self.watermarkFilters = activeWatermarks.union(
            WatermarkTermParser.parse(customWatermarks)
        )
        self.ignoreCase = ignoreCase
        self.eraseImageWatermark = eraseImageWatermark
        self.targetPages = try PageRangeParser.parse(
            pageRangeString,
            maximumPageCount: maximumPageCount
        )
    }
}

// MARK: - 水印词解析

/// 统一解析用户输入的水印词，保证 PDF 引擎与 AI 提示词使用完全相同的结果。
enum WatermarkTermParser {
    static func parse(_ rawText: String) -> Set<String> {
        let terms = rawText
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(terms)
    }
}
