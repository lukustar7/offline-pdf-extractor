import Foundation

// MARK: - PDF 底层去水印模式

/// 描述 PDF 引擎内部采用的去水印方式。
/// 该类型保留为独立模型，便于日志、测试和后续扩展，不与具体界面绑定。
enum WatermarkRemovalMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "智能诊断匹配（推荐）"
    case textLayerOnly = "纯文本过滤（矢量文字版专用）"
    case textWatermarkOverScan = "OCR文字识别 + 水印词过滤（扫描件+文字水印）"
    case scannedWatermarkOverScan = "图像背景净化 + OCR识别（全扫描件+纸印水印）"

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
            return "可选文字 + 文字水印"
        case .scannedTextWithTextWatermark:
            return "扫描正文 + 文字水印"
        case .fullyScanned:
            return "扫描正文 + 纸印水印"
        }
    }

    var subtitle: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "常规电子文档 · 1秒极速导出\n保留清晰排版与原图"
        case .scannedTextWithTextWatermark:
            return "纸质拍照扫描 · 后加文字水印\n原生高精识别与智能切图"
        case .fullyScanned:
            return "全纸质扫描件 · 水印印在纸上\n背景底纹自动净化后识别"
        }
    }

    var systemImage: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "text.badge.checkmark"
        case .scannedTextWithTextWatermark:
            return "doc.viewfinder"
        case .fullyScanned:
            return "sparkles.rectangle.stack"
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
            return .textLayerOnly
        case .scannedTextWithTextWatermark:
            return .textWatermarkOverScan
        case .fullyScanned:
            return .scannedWatermarkOverScan
        }
    }

    var statusDescription: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "读取 PDF 文本层与高清插图，极速提取，无需重新 OCR。"
        case .scannedTextWithTextWatermark:
            return "滤除文字水印，调用苹果原生 Vision OCR 识别图像文字，并精准截取插图。"
        case .fullyScanned:
            return "自动执行背景底纹与印章多通道净化预处理，随后高精识别文字与插图。"
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
    let removeLightWatermarks: Bool
    let removeColorStamps: Bool
    let targetPages: [Int]

    /// 构建请求时立即校验页码，并合并自动识别与手动输入的水印词。
    init(
        scenario: PDFProcessingScenario,
        activeWatermarks: Set<String>,
        customWatermarks: String,
        ignoreCase: Bool,
        eraseImageWatermark: Bool = false,
        removeLightWatermarks: Bool = true,
        removeColorStamps: Bool = false,
        pageRangeString: String,
        maximumPageCount: Int
    ) throws {
        self.scenario = scenario
        self.watermarkFilters = activeWatermarks.union(
            WatermarkTermParser.parse(customWatermarks)
        )
        self.ignoreCase = ignoreCase
        self.eraseImageWatermark = eraseImageWatermark
        self.removeLightWatermarks = removeLightWatermarks
        self.removeColorStamps = removeColorStamps
        self.targetPages = try PageRangeParser.parse(
            pageRangeString,
            maximumPageCount: maximumPageCount
        )
    }
}

// MARK: - 水印词解析

/// 统一解析用户输入的水印词，保证提取引擎过滤时使用精确去重的结果。
enum WatermarkTermParser {
    static func parse(_ rawText: String) -> Set<String> {
        let terms = rawText
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(terms)
    }
}
