import Foundation

// MARK: - AI 服务端点

/// AI 服务地址校验错误。只接受明确的 HTTP 或 HTTPS 基础地址。
enum AIEndpointError: LocalizedError, Equatable, Sendable {
    case emptyAddress
    case invalidAddress
    case unsupportedScheme
    case missingHost
    case embeddedCredentials
    case queryOrFragmentNotAllowed

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "AI 服务地址不能为空。"
        case .invalidAddress:
            return "AI 服务地址格式无效。"
        case .unsupportedScheme:
            return "AI 服务地址必须以 http:// 或 https:// 开头。"
        case .missingHost:
            return "AI 服务地址缺少主机名。"
        case .embeddedCredentials:
            return "请勿把账号或密码直接写入 AI 服务地址。"
        case .queryOrFragmentNotAllowed:
            return "AI 服务基础地址不能包含查询参数或页面片段。"
        }
    }
}

/// 表示经过严格校验和标准化的 OpenAI 兼容端点。
struct AIEndpoint: Equatable, Sendable {
    let baseURL: URL
    let isLocalNetwork: Bool

    var usesTLS: Bool {
        baseURL.scheme?.lowercased() == "https"
    }

    init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIEndpointError.emptyAddress
        }
        guard var components = URLComponents(string: trimmed) else {
            throw AIEndpointError.invalidAddress
        }

        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw AIEndpointError.unsupportedScheme
        }
        guard let host = components.host?.lowercased(), !host.isEmpty else {
            throw AIEndpointError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw AIEndpointError.embeddedCredentials
        }
        guard components.query == nil, components.fragment == nil else {
            throw AIEndpointError.queryOrFragmentNotAllowed
        }

        // 统一移除末尾斜杠，后续追加 models 或 chat/completions 时不会产生双斜杠。
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let normalizedURL = components.url else {
            throw AIEndpointError.invalidAddress
        }

        self.baseURL = normalizedURL
        self.isLocalNetwork = Self.isLocalHost(host)
    }

    var modelsURL: URL {
        baseURL.appendingPathComponent("models", isDirectory: false)
    }

    var chatCompletionsURL: URL {
        baseURL
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("completions", isDirectory: false)
    }

    /// 只按完整主机名或合法数字地址判断，避免把 10.example.com 误报为内网地址。
    private static func isLocalHost(_ host: String) -> Bool {
        // 不同 Foundation 版本可能保留 IPv6 URL 的方括号，判断前统一清理。
        let normalizedHost = host
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".[]"))

        if normalizedHost == "localhost" || normalizedHost.hasSuffix(".localhost") {
            return true
        }
        if normalizedHost == "::1" {
            return true
        }

        if let ipv4 = parseIPv4(normalizedHost) {
            let first = ipv4[0]
            let second = ipv4[1]
            return first == 10
                || first == 127
                || (first == 169 && second == 254)
                || (first == 172 && (16...31).contains(second))
                || (first == 192 && second == 168)
                || ipv4 == [0, 0, 0, 0]
        }

        // 只有包含冒号的合法 URL 主机才可能是 IPv6，普通域名不能靠 fc/fd 前缀伪装。
        guard normalizedHost.contains(":") else { return false }

        // IPv6 本地回环、唯一本地地址 fc00::/7 与链路本地地址 fe80::/10。
        let addressWithoutZone = normalizedHost.split(separator: "%", maxSplits: 1).first.map(String.init) ?? normalizedHost
        if addressWithoutZone.hasPrefix("fc") || addressWithoutZone.hasPrefix("fd") {
            return true
        }
        if addressWithoutZone.count >= 3 {
            let prefix = addressWithoutZone.prefix(3)
            if ["fe8", "fe9", "fea", "feb"].contains(prefix) {
                return true
            }
        }

        if addressWithoutZone.hasPrefix("::ffff:") {
            let mappedIPv4 = String(addressWithoutZone.dropFirst("::ffff:".count))
            if let ipv4 = parseIPv4(mappedIPv4) {
                return ipv4[0] == 10
                    || ipv4[0] == 127
                    || (ipv4[0] == 172 && (16...31).contains(ipv4[1]))
                    || (ipv4[0] == 192 && ipv4[1] == 168)
            }
        }

        return false
    }

    private static func parseIPv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var numbers: [Int] = []
        numbers.reserveCapacity(4)
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isNumber }),
                  let number = Int(part),
                  (0...255).contains(number) else {
                return nil
            }
            numbers.append(number)
        }
        return numbers
    }
}
