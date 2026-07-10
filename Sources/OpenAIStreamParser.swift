import Foundation

// MARK: - OpenAI 流式响应解析

/// 流式响应无法继续解析时返回的明确错误。
enum OpenAIStreamParserError: LocalizedError, Equatable, Sendable {
    case bufferLimitExceeded
    case malformedPayload
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .bufferLimitExceeded:
            return "AI 返回了超长且未分行的数据，已停止接收以避免内存持续增长。"
        case .malformedPayload:
            return "AI 服务返回了无法解析的流式数据。"
        case .serviceError(let message):
            return "AI 服务返回错误：\(message)"
        }
    }
}

/// 增量解析 OpenAI 兼容的 SSE 数据，同时兼容最后一行没有换行符的响应。
struct OpenAIStreamParser: Sendable {
    private static let maximumBufferedBytes = 1_048_576
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [String] {
        buffer.append(data)
        guard buffer.count <= Self.maximumBufferedBytes else {
            throw OpenAIStreamParserError.bufferLimitExceeded
        }
        return try drainCompleteLines()
    }

    mutating func finish() throws -> [String] {
        var contents = try drainCompleteLines()
        guard !buffer.isEmpty else { return contents }

        let finalLine = buffer
        buffer.removeAll(keepingCapacity: false)
        if let content = try parseLine(finalLine) {
            contents.append(content)
        }
        return contents
    }

    private mutating func drainCompleteLines() throws -> [String] {
        var contents: [String] = []
        while let lineEnd = buffer.firstIndex(of: 10) {
            let line = buffer.subdata(in: 0..<lineEnd)
            buffer.removeSubrange(0...lineEnd)
            if let content = try parseLine(line) {
                contents.append(content)
            }
        }
        return contents
    }

    private func parseLine(_ lineData: Data) throws -> String? {
        guard let rawLine = String(data: lineData, encoding: .utf8) else {
            throw OpenAIStreamParserError.malformedPayload
        }

        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        // SSE 注释与控制字段不包含正文，直接忽略。
        if line.hasPrefix(":")
            || line.hasPrefix("event:")
            || line.hasPrefix("id:")
            || line.hasPrefix("retry:") {
            return nil
        }

        let payload: String
        if line.hasPrefix("data:") {
            payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // 某些本地兼容端点直接逐行返回 JSON，不带 SSE 的 data: 前缀。
            payload = line
        }

        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIStreamParserError.malformedPayload
        }

        if let errorObject = json["error"] as? [String: Any] {
            let message = (errorObject["message"] as? String) ?? "未知服务错误"
            throw OpenAIStreamParserError.serviceError(message)
        }

        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first {
            if let delta = firstChoice["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                return content.isEmpty ? nil : content
            }
            // 兼容服务忽略 stream=true 后返回的单次完整响应。
            if let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.isEmpty ? nil : content
            }
        }

        return nil
    }
}
