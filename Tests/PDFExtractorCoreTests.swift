import Darwin
import Foundation

// MARK: - 零依赖测试基础设施

/// 当前 Command Line Tools 未附带 XCTest/Testing 运行库，因此使用轻量执行器。
/// 测试仍由 Swift 6 编译器编译真实生产源码，任何失败都会让进程返回非零状态。
private struct AssertionFailure: Error, CustomStringConvertible {
    let description: String
}

private struct CoreTestSuite {
    private(set) var passedCount = 0
    private(set) var failures: [String] = []

    mutating func run(_ name: String, body: () throws -> Void) {
        do {
            try body()
            passedCount += 1
            print("通过：\(name)")
        } catch {
            failures.append("\(name)：\(error)")
            print("失败：\(name)：\(error)")
        }
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("核心逻辑测试完成：\(passedCount) 项全部通过。")
            exit(EXIT_SUCCESS)
        }

        print("核心逻辑测试失败：\(failures.count) 项失败，\(passedCount) 项通过。")
        exit(EXIT_FAILURE)
    }
}

private func require(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String
) throws {
    guard try condition() else { throw AssertionFailure(description: message) }
}

private func requireThrows<ExpectedError>(
    _ expectedError: ExpectedError,
    operation: () throws -> Void
) throws where ExpectedError: Error & Equatable {
    do {
        try operation()
    } catch let actualError as ExpectedError {
        try require(actualError == expectedError, "错误不匹配：\(actualError)")
        return
    }
    throw AssertionFailure(description: "预期抛出 \(expectedError)，但操作成功或抛出了其他错误。")
}

// MARK: - 核心逻辑测试入口

@main
struct PDFExtractorCoreTests {
    static func main() {
        var suite = CoreTestSuite()
        runPageRangeTests(in: &suite)
        runEndpointTests(in: &suite)
        runStreamParserTests(in: &suite)
        suite.finish()
    }

    private static func runPageRangeTests(in suite: inout CoreTestSuite) {
        suite.run("空页码输入选择全部页面") {
            let pages = try PageRangeParser.parse("", maximumPageCount: 4)
            try require(pages == [1, 2, 3, 4], "全部页码结果不正确")
        }

        suite.run("混合连接符标准化并去重") {
            let pages = try PageRangeParser.parse(
                "1-3， 6, 8—7, 3",
                maximumPageCount: 10
            )
            try require(pages == [1, 2, 3, 6, 7, 8], "混合页码解析结果不正确")
        }

        suite.run("无效页码不会回退为全部页面") {
            try requireThrows(PageRangeError.invalidItem("abc")) {
                _ = try PageRangeParser.parse("abc", maximumPageCount: 20)
            }
        }

        suite.run("越界页码返回明确错误") {
            try requireThrows(
                PageRangeError.pageOutOfBounds(page: 99, maximum: 12)
            ) {
                _ = try PageRangeParser.parse("1-99", maximumPageCount: 12)
            }
        }

        suite.run("零页文档不会创建非法闭区间") {
            try requireThrows(PageRangeError.documentHasNoPages) {
                _ = try PageRangeParser.parse("", maximumPageCount: 0)
            }
        }

        suite.run("提取请求冻结校验后的输入") {
            let request = try PDFExtractionRequest(
                scenario: .fullyScanned,
                activeWatermarks: ["内部资料"],
                customWatermarks: "样张，内部资料\nCONFIDENTIAL",
                ignoreCase: true,
                eraseImageWatermark: false,
                pageRangeString: "2-3",
                maximumPageCount: 5
            )
            try require(request.targetPages == [2, 3], "请求页码不正确")
            try require(
                request.watermarkFilters == ["内部资料", "样张", "CONFIDENTIAL"],
                "水印词没有正确合并去重"
            )
        }
    }

    private static func runEndpointTests(in suite: inout CoreTestSuite) {
        suite.run("端点末尾斜杠不会形成重复路径") {
            let endpoint = try AIEndpoint("http://localhost:11434/v1/")
            try require(
                endpoint.modelsURL.absoluteString == "http://localhost:11434/v1/models",
                "模型列表路径不正确"
            )
            try require(
                endpoint.chatCompletionsURL.absoluteString
                    == "http://localhost:11434/v1/chat/completions",
                "对话接口路径不正确"
            )
            try require(endpoint.isLocalNetwork, "localhost 应识别为本地地址")
            try require(!endpoint.usesTLS, "HTTP 地址不应标记为 TLS")
        }

        suite.run("私有 IPv4 与 IPv6 回环地址属于本地网络") {
            try require(
                AIEndpoint("http://172.16.3.8:1234/v1").isLocalNetwork,
                "私有 IPv4 未识别为本地地址"
            )
            try require(
                AIEndpoint("http://[::1]:11434/v1").isLocalNetwork,
                "IPv6 回环地址未识别为本地地址"
            )
        }

        suite.run("相似域名不能伪装成私有地址") {
            try require(
                !AIEndpoint("https://10.example.com/v1").isLocalNetwork,
                "10.example.com 被错误识别为内网地址"
            )
            try require(
                !AIEndpoint("https://fcevil.example/v1").isLocalNetwork,
                "fc 前缀域名被错误识别为 IPv6 本地地址"
            )
            try require(
                !AIEndpoint("https://192.168.example.com/v1").isLocalNetwork,
                "192.168 前缀域名被错误识别为内网地址"
            )
        }

        suite.run("公网 HTTPS 被识别为外部加密端点") {
            let endpoint = try AIEndpoint("https://api.example.com/v1")
            try require(!endpoint.isLocalNetwork, "公网域名不应识别为本地地址")
            try require(endpoint.usesTLS, "HTTPS 地址应标记为 TLS")
        }

        suite.run("拒绝不支持的协议与内嵌凭证") {
            try requireThrows(AIEndpointError.unsupportedScheme) {
                _ = try AIEndpoint("file:///tmp/model")
            }
            try requireThrows(AIEndpointError.embeddedCredentials) {
                _ = try AIEndpoint("https://user:secret@example.com/v1")
            }
        }
    }

    private static func runStreamParserTests(in suite: inout CoreTestSuite) {
        suite.run("跨网络分包的 JSON 会被重新拼合") {
            var parser = OpenAIStreamParser()
            let line = try makeDeltaLine("你好")
            let splitIndex = line.count / 2

            try require(
                try parser.append(Data(line.prefix(splitIndex))).isEmpty,
                "不完整数据不应提前产出正文"
            )
            try require(
                try parser.append(Data(line.suffix(from: splitIndex))) == ["你好"],
                "分包数据没有正确拼合"
            )
            try require(try parser.finish().isEmpty, "完成后不应重复产出正文")
        }

        suite.run("末行没有换行符时仍可解析") {
            var parser = OpenAIStreamParser()
            let line = try makeDeltaLine("完成", includeSpaceAfterDataPrefix: false)

            try require(
                try parser.append(Data(line.dropLast())).isEmpty,
                "没有换行符时应等待 finish"
            )
            try require(try parser.finish() == ["完成"], "末行正文丢失")
        }

        suite.run("兼容非流式完整响应") {
            var parser = OpenAIStreamParser()
            let object: [String: Any] = [
                "choices": [["message": ["content": "完整结果"]]]
            ]
            var line = try JSONSerialization.data(withJSONObject: object)
            line.append(10)
            try require(
                try parser.append(line) == ["完整结果"],
                "非流式响应没有被兼容解析"
            )
        }

        suite.run("服务错误正文转换为可见错误") {
            var parser = OpenAIStreamParser()
            let object: [String: Any] = ["error": ["message": "model not found"]]
            var line = Data("data: ".utf8)
            line.append(try JSONSerialization.data(withJSONObject: object))
            line.append(10)

            try requireThrows(
                OpenAIStreamParserError.serviceError("model not found")
            ) {
                _ = try parser.append(line)
            }
        }

        suite.run("未分行缓冲超过一 MiB 时停止解析") {
            var parser = OpenAIStreamParser()
            let oversizedLine = Data(repeating: 65, count: 1_048_577)
            try requireThrows(OpenAIStreamParserError.bufferLimitExceeded) {
                _ = try parser.append(oversizedLine)
            }
        }
    }

    private static func makeDeltaLine(
        _ content: String,
        includeSpaceAfterDataPrefix: Bool = true
    ) throws -> Data {
        let object: [String: Any] = [
            "choices": [["delta": ["content": content]]]
        ]
        let prefix = includeSpaceAfterDataPrefix ? "data: " : "data:"
        var line = Data(prefix.utf8)
        line.append(try JSONSerialization.data(withJSONObject: object))
        line.append(10)
        return line
    }
}
