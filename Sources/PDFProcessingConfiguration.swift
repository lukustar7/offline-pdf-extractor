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
            return "直接提取文字"
        case .scannedTextWithTextWatermark:
            return "扫描件图文识别"
        case .fullyScanned:
            return "强力去印识别"
        }
    }

    var subtitle: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "常规活字 1秒搞定\n保留排版与高清插图"
        case .scannedTextWithTextWatermark:
            return "清晰扫描·拍照图片\n高精文字识别与切图"
        case .fullyScanned:
            return "红章公章·深色底纹\n先滤印净化后再识别"
        }
    }

    var systemImage: String {
        switch self {
        case .electronicTextWithTextWatermark:
            return "bolt.fill"
        case .scannedTextWithTextWatermark:
            return "doc.viewfinder.fill"
        case .fullyScanned:
            return "shield.checkerboard"
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
            return "读取 PDF 文本层与高清插图，极速提取，不重新 OCR。"
        case .scannedTextWithTextWatermark:
            return "使用苹果原生 Vision OCR 识别扫描图像文字，并智能定位截取插图。"
        case .fullyScanned:
            return "执行红通道公章消除与色阶洗白预处理后识别文字，并智能定位截取插图。"
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
