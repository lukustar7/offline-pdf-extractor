import SwiftUI

// MARK: - AI 服务错误

private enum AIServiceError: LocalizedError, Sendable {
    case invalidResponse
    case responseTooLarge
    case redirectNotAllowed
    case httpStatus(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "AI 服务没有返回有效的 HTTP 响应。"
        case .responseTooLarge:
            return "AI 模型列表响应超过 2 MiB，已停止解析。"
        case .redirectNotAllowed:
            return "AI 服务尝试跳转到其他地址，已阻止请求以避免文本或密钥外发。"
        case .httpStatus(let code, let message):
            if message.isEmpty {
                return "AI 服务返回 HTTP \(code)。"
            }
            return "AI 服务返回 HTTP \(code)：\(message)"
        }
    }
}

// MARK: - 本地 AI 净化状态引擎

/// 管理 OpenAI 兼容端点、模型列表和按页串行净化任务。
@MainActor
final class AIProcessingEngine: ObservableObject {
    @Published var isAIProcessing = false
    @Published var aiProgressStatus = ""
    @Published var aiPagesText: [Int: String] = [:]
    @Published var aiModels: [String] = []
    @Published var isAIFetchingModels = false
    @Published var aiTotalChunks = 0
    @Published var aiCurrentChunkIndex = 0
    @Published var isExternalURLWarning = false
    @Published var endpointValidationError: String?
    @Published var aiApiKey = ""
    @Published private(set) var allowsExternalEndpoint = false

    @AppStorage("aiApiBaseUrl") var aiApiBaseUrl = "http://localhost:11434/v1"
    @AppStorage("aiSelectedModel") var aiSelectedModel = ""

    private var pendingPagesToProcess: [(pageIndex: Int, text: String)] = []
    private var currentPageIndexProcessing: Int?
    private var currentAISession: URLSession?
    private var currentAITask: URLSessionDataTask?
    private var currentStreamDelegate: AIStreamDelegate?
    private var currentStreamRequestID: UUID?
    private var modelFetchTask: Task<Void, Never>?
    private var modelFetchToken: UUID?

    private var currentAIToken = UUID()
    private var currentPageText = ""
    private var pendingOutputBuffer = ""
    private var lastUIUpdateTime = Date.distantPast

    private var activeEndpoint: AIEndpoint?
    private var activeModel = ""
    private var activeAPIKey = ""
    private var activeSystemPrompt = ""
    private var approvedExternalEndpoint: URL?

    private struct AIModelResponse: Decodable {
        let data: [AIModelData]
    }

    private struct AIModelData: Decodable {
        let id: String
    }

    private struct ChatCompletionRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let stream: Bool
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    init() {
        aiApiKey = KeychainHelper.shared.read() ?? ""
        checkURLSafety(urlString: aiApiBaseUrl)
    }

    // MARK: 端点与凭证

    /// 校验基础地址并更新界面提示。公网地址仍允许使用，但会显示明确的数据外发警告。
    func checkURLSafety(urlString: String) {
        do {
            let endpoint = try AIEndpoint(urlString)
            endpointValidationError = nil
            isExternalURLWarning = !endpoint.isLocalNetwork
            if endpoint.isLocalNetwork || approvedExternalEndpoint != endpoint.baseURL {
                approvedExternalEndpoint = nil
                allowsExternalEndpoint = false
            }
        } catch {
            endpointValidationError = error.localizedDescription
            isExternalURLWarning = false
            approvedExternalEndpoint = nil
            allowsExternalEndpoint = false
        }
    }

    /// 外部地址授权只绑定当前完整基础 URL，用户修改任何部分后必须重新确认。
    func setExternalEndpointPermission(_ isAllowed: Bool) {
        guard let endpoint = try? AIEndpoint(aiApiBaseUrl),
              !endpoint.isLocalNetwork,
              isAllowed else {
            approvedExternalEndpoint = nil
            allowsExternalEndpoint = false
            return
        }
        approvedExternalEndpoint = endpoint.baseURL
        allowsExternalEndpoint = true
    }

    /// 用户确认后才写入钥匙串，避免编辑过程中反复执行同步安全存储 I/O。
    func saveAPIKey() {
        if aiApiKey.isEmpty {
            if KeychainHelper.shared.delete() {
                aiProgressStatus = "已清除保存的 API 密钥。"
            } else {
                aiProgressStatus = "错误：无法清除钥匙串中的 API 密钥。"
            }
            return
        }

        if KeychainHelper.shared.save(aiApiKey) {
            aiProgressStatus = "API 密钥已保存到 macOS 钥匙串。"
        } else {
            aiProgressStatus = "错误：API 密钥写入 macOS 钥匙串失败。"
        }
    }

    func clearAPIKey() {
        aiApiKey = ""
        saveAPIKey()
    }

    // MARK: 模型列表

    /// 获取端点提供的模型列表；快速重复点击时，仅最后一次请求可以更新界面。
    func fetchAIModels() {
        modelFetchTask?.cancel()

        let endpoint: AIEndpoint
        do {
            endpoint = try AIEndpoint(aiApiBaseUrl)
            checkURLSafety(urlString: aiApiBaseUrl)
        } catch {
            aiProgressStatus = "错误：\(error.localizedDescription)"
            return
        }
        guard aiApiKey.isEmpty || endpoint.isLocalNetwork || endpoint.usesTLS else {
            aiProgressStatus = "错误：公网 HTTP 地址不会发送 API 密钥，请改用 HTTPS 或清除密钥。"
            return
        }
        guard endpoint.isLocalNetwork || approvedExternalEndpoint == endpoint.baseURL else {
            aiProgressStatus = "错误：使用外部 AI 地址前，请在左侧 AI 设置中明确允许本次连接。"
            return
        }

        let token = UUID()
        modelFetchToken = token
        isAIFetchingModels = true
        aiProgressStatus = "正在获取模型列表..."

        var request = URLRequest(url: endpoint.modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if !aiApiKey.isEmpty {
            request.setValue("Bearer \(aiApiKey)", forHTTPHeaderField: "Authorization")
        }

        modelFetchTask = Task { [weak self] in
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.httpCookieStorage = nil
                let session = URLSession(
                    configuration: configuration,
                    delegate: NoRedirectURLSessionDelegate(),
                    delegateQueue: nil
                )
                defer { session.invalidateAndCancel() }

                let (bytes, response) = try await session.bytes(for: request)
                try Task.checkCancellation()

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIServiceError.invalidResponse
                }
                let isSuccessfulResponse = (200...299).contains(httpResponse.statusCode)
                let maximumResponseBytes = isSuccessfulResponse ? 2_097_152 : 65_536
                var data = Data()
                data.reserveCapacity(min(maximumResponseBytes, 65_536))
                var responseWasTruncated = false

                for try await byte in bytes {
                    if data.count >= maximumResponseBytes {
                        responseWasTruncated = true
                        break
                    }
                    data.append(byte)
                }

                try Self.validateHTTPResponse(response, body: data)
                guard !responseWasTruncated else {
                    throw AIServiceError.responseTooLarge
                }

                let decoded = try JSONDecoder().decode(AIModelResponse.self, from: data)
                var seenModels = Set<String>()
                let modelIDs = decoded.data.compactMap { modelData -> String? in
                    let modelID = modelData.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !modelID.isEmpty, seenModels.insert(modelID).inserted else { return nil }
                    return modelID
                }

                guard let self,
                      self.modelFetchToken == token else { return }
                self.aiModels = modelIDs
                if let firstModel = modelIDs.first,
                   self.aiSelectedModel.isEmpty || !modelIDs.contains(self.aiSelectedModel) {
                    self.aiSelectedModel = firstModel
                }
                self.aiProgressStatus = modelIDs.isEmpty
                    ? "服务已连接，但没有返回可用模型。"
                    : "已获取 \(modelIDs.count) 个模型。"
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.modelFetchToken == token else { return }
                self.aiProgressStatus = "错误：获取模型失败，\(error.localizedDescription)"
            }

            guard let self,
                  self.modelFetchToken == token else { return }
            self.isAIFetchingModels = false
            self.modelFetchToken = nil
            self.modelFetchTask = nil
        }
    }

    // MARK: 文本净化

    /// 按物理页串行发送文本，避免本地模型同时处理多页造成显存拥塞。
    func processTextWithAI(
        extractedPages: [Int: String],
        targetPages: [Int],
        systemPrompt: String
    ) {
        cancelAIProcessing(showStatus: false)

        let endpoint: AIEndpoint
        do {
            endpoint = try AIEndpoint(aiApiBaseUrl)
            checkURLSafety(urlString: aiApiBaseUrl)
        } catch {
            aiProgressStatus = "错误：\(error.localizedDescription)"
            return
        }
        guard aiApiKey.isEmpty || endpoint.isLocalNetwork || endpoint.usesTLS else {
            aiProgressStatus = "错误：公网 HTTP 地址不会发送 API 密钥，请改用 HTTPS 或清除密钥。"
            return
        }
        guard endpoint.isLocalNetwork || approvedExternalEndpoint == endpoint.baseURL else {
            aiProgressStatus = "错误：使用外部 AI 地址前，请在左侧 AI 设置中明确允许本次连接。"
            return
        }

        let model = aiSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            aiProgressStatus = "错误：请先获取或填写 AI 模型名称。"
            return
        }

        let uniqueTargetPages = Array(Set(targetPages)).sorted()
        let pages = uniqueTargetPages.compactMap { pageNumber -> (pageIndex: Int, text: String)? in
            guard let text = extractedPages[pageNumber],
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (pageIndex: pageNumber, text: text)
        }
        guard !pages.isEmpty else {
            aiProgressStatus = "错误：目标页面没有可净化文本，请先提取文字。"
            return
        }

        let token = UUID()
        currentAIToken = token
        activeEndpoint = endpoint
        activeModel = model
        activeAPIKey = aiApiKey
        activeSystemPrompt = systemPrompt
        pendingPagesToProcess = pages
        aiTotalChunks = pages.count
        aiCurrentChunkIndex = 0
        isAIProcessing = true

        for page in pages {
            aiPagesText[page.pageIndex] = ""
        }
        processNextPage(token: token)
    }

    private func processNextPage(token: UUID) {
        guard isAIProcessing, currentAIToken == token else { return }

        guard !pendingPagesToProcess.isEmpty else {
            aiProgressStatus = "本地 AI 净化已完成。"
            isAIProcessing = false
            activeEndpoint = nil
            activeModel = ""
            activeAPIKey = ""
            activeSystemPrompt = ""
            currentPageIndexProcessing = nil
            return
        }

        guard let endpoint = activeEndpoint else {
            finishAIProcessingWithError("AI 服务地址已失效。")
            return
        }

        let nextPage = pendingPagesToProcess.removeFirst()
        currentPageIndexProcessing = nextPage.pageIndex
        currentPageText = ""
        pendingOutputBuffer = ""
        currentPageText = ""
        lastUIUpdateTime = Date.distantPast
        aiProgressStatus = "本地 AI 正在净化第 \(nextPage.pageIndex) 页（\(aiCurrentChunkIndex + 1) / \(aiTotalChunks)）..."

        let pageInstruction = """

        【当前任务】
        输入内容来自 PDF 第 \(nextPage.pageIndex) 页。只输出净化排版后的本页正文；不要输出开场白、总结、代码块围栏或其他说明。保持原文含义和自然段落。
        """
        let payload = ChatCompletionRequest(
            model: activeModel,
            messages: [
                Message(role: "system", content: activeSystemPrompt + pageInstruction),
                Message(role: "user", content: nextPage.text)
            ],
            temperature: 0.1,
            stream: true
        )

        var request = URLRequest(url: endpoint.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        if !activeAPIKey.isEmpty {
            request.setValue("Bearer \(activeAPIKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            finishAIProcessingWithError("无法生成 AI 请求数据：\(error.localizedDescription)")
            return
        }

        let requestID = UUID()
        currentStreamRequestID = requestID
        let streamDelegate = AIStreamDelegate()
        streamDelegate.onDeltaReceived = { [weak self] content in
            Task { @MainActor [weak self] in
                guard let self,
                      self.currentAIToken == token,
                      self.currentStreamRequestID == requestID else { return }
                self.appendDeltaText(content)
            }
        }
        streamDelegate.onComplete = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self,
                      self.currentAIToken == token,
                      self.currentStreamRequestID == requestID else { return }
                self.handlePageComplete(error: error, token: token)
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(
            configuration: configuration,
            delegate: streamDelegate,
            delegateQueue: nil
        )
        let task = session.dataTask(with: request)

        currentStreamDelegate = streamDelegate
        currentAISession = session
        currentAITask = task
        task.resume()
    }

    private func handlePageComplete(error: Error?, token: UUID) {
        guard isAIProcessing, currentAIToken == token else { return }
        flushPendingAIText()

        currentAITask = nil
        currentAISession?.finishTasksAndInvalidate()
        currentAISession = nil
        currentStreamDelegate = nil
        currentStreamRequestID = nil

        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled { return }
            finishAIProcessingWithError("AI 生成中断：\(error.localizedDescription)")
            return
        }

        if let pageNumber = currentPageIndexProcessing {
            aiPagesText[pageNumber] = currentPageText
        }
        aiCurrentChunkIndex += 1
        currentPageIndexProcessing = nil
        processNextPage(token: token)
    }

    /// 取消会同时更换任务令牌；旧代理即使稍后回调，也无法修改新任务状态。
    func cancelAIProcessing(showStatus: Bool = true) {
        currentAIToken = UUID()
        pendingPagesToProcess.removeAll()
        currentPageIndexProcessing = nil
        currentStreamRequestID = nil
        pendingOutputBuffer = ""

        currentAITask?.cancel()
        currentAITask = nil
        currentAISession?.invalidateAndCancel()
        currentAISession = nil
        currentStreamDelegate = nil
        isAIProcessing = false

        activeEndpoint = nil
        activeModel = ""
        activeAPIKey = ""
        activeSystemPrompt = ""

        if showStatus {
            aiProgressStatus = "已取消 AI 净化流程。"
        }
    }

    /// 关闭 PDF 时清除文档相关结果，但保留端点、模型和钥匙串偏好。
    func clear() {
        cancelAIProcessing(showStatus: false)
        modelFetchTask?.cancel()
        modelFetchTask = nil
        modelFetchToken = nil
        isAIFetchingModels = false
        aiPagesText = [:]
        aiProgressStatus = ""
        aiTotalChunks = 0
        aiCurrentChunkIndex = 0
    }

    private func appendDeltaText(_ text: String) {
        pendingOutputBuffer += text
        let now = Date()
        if now.timeIntervalSince(lastUIUpdateTime) >= 0.1 {
            flushPendingAIText()
            lastUIUpdateTime = now
        }
    }

    private func flushPendingAIText() {
        guard !pendingOutputBuffer.isEmpty else { return }
        let text = pendingOutputBuffer
        pendingOutputBuffer = ""
        currentPageText += text

        if let pageNumber = currentPageIndexProcessing {
            aiPagesText[pageNumber] = (aiPagesText[pageNumber] ?? "") + text
        }
    }

    private func finishAIProcessingWithError(_ message: String) {
        currentAIToken = UUID()
        aiProgressStatus = "错误：\(message)"
        isAIProcessing = false
        pendingPagesToProcess.removeAll()
        pendingOutputBuffer = ""
        currentPageText = ""
        currentPageIndexProcessing = nil
        currentStreamRequestID = nil
        currentAITask?.cancel()
        currentAITask = nil
        currentAISession?.invalidateAndCancel()
        currentAISession = nil
        currentStreamDelegate = nil
        activeEndpoint = nil
        activeModel = ""
        activeAPIKey = ""
        activeSystemPrompt = ""
    }

    private static func validateHTTPResponse(_ response: URLResponse, body: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIServiceError.httpStatus(
                code: httpResponse.statusCode,
                message: responseErrorMessage(from: body)
            )
        }
    }

    private static func responseErrorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(300))
        }
        let plainText = String(data: data.prefix(2_048), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ") ?? ""
        return String(plainText.prefix(300))
    }
}

// MARK: - URLSession 流代理

/// URLSession 默认使用串行代理队列；`@unchecked Sendable` 明确记录该可变状态只在该队列访问。
final class AIStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private static let maximumErrorBodyBytes = 65_536

    private var parser = OpenAIStreamParser()
    private var httpErrorStatusCode: Int?
    private var httpErrorBody = Data()
    private var parsingError: Error?
    private var hasReceivedContent = false

    var onDeltaReceived: (@Sendable (String) -> Void)?
    var onComplete: (@Sendable (Error?) -> Void)?

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            parsingError = AIServiceError.invalidResponse
            completionHandler(.cancel)
            return
        }
        if !(200...299).contains(httpResponse.statusCode) {
            httpErrorStatusCode = httpResponse.statusCode
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        parsingError = AIServiceError.redirectNotAllowed
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        if httpErrorStatusCode != nil {
            appendBoundedErrorBody(data)
            return
        }

        do {
            emit(try parser.append(data))
        } catch {
            parsingError = error
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let statusCode = httpErrorStatusCode {
            onComplete?(makeHTTPError(statusCode: statusCode))
            return
        }
        if let parsingError {
            onComplete?(parsingError)
            return
        }

        do {
            emit(try parser.finish())
        } catch {
            onComplete?(error)
            return
        }

        if error == nil && !hasReceivedContent {
            onComplete?(
                NSError(
                    domain: "AIStreamDelegate",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "AI 服务没有返回可解析的正文，请确认端点兼容 OpenAI chat/completions 接口。"
                    ]
                )
            )
            return
        }
        onComplete?(error)
    }

    private func emit(_ contents: [String]) {
        for content in contents where !content.isEmpty {
            hasReceivedContent = true
            onDeltaReceived?(content)
        }
    }

    private func appendBoundedErrorBody(_ data: Data) {
        let remainingBytes = Self.maximumErrorBodyBytes - httpErrorBody.count
        guard remainingBytes > 0 else { return }
        httpErrorBody.append(data.prefix(remainingBytes))
    }

    private func makeHTTPError(statusCode: Int) -> NSError {
        let message = Self.errorMessage(from: httpErrorBody)
        let description = message.isEmpty
            ? "AI 服务返回 HTTP \(statusCode)，没有附带错误正文。"
            : "AI 服务返回 HTTP \(statusCode)：\(message)"
        return NSError(
            domain: "AIStreamDelegate",
            code: statusCode,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    private static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(300))
        }
        let plainText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ") ?? ""
        return String(plainText.prefix(300))
    }
}

// MARK: - 禁止重定向的普通请求代理

/// 模型列表请求同样不允许离开用户填写的原始端点。
final class NoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
