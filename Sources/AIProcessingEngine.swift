import SwiftUI

// MARK: - 本地 AI 净化服务引擎 (纯 Swift 类解耦版)
class AIProcessingEngine: ObservableObject {
    @Published var isAIProcessing = false
    @Published var aiProgressStatus: String = ""
    @Published var aiResultText: String = ""
    @Published var aiTxtFileURL: URL?
    @Published var aiMdFileURL: URL?
    
    @Published var aiModels: [String] = []
    @Published var isAIFetchingModels = false
    
    // === 本地 AI 串行分片推理进度 ===
    @Published var aiTotalChunks: Int = 0
    @Published var aiCurrentChunkIndex: Int = 0
    
    // === 离线安全校验警示状态 ===
    @Published var isExternalURLWarning = false
    
    // 使用 @AppStorage 自动将关键设置持久化到本地 UserDefaults 中
    @AppStorage("aiApiBaseUrl") var aiApiBaseUrl: String = "http://localhost:11434/v1"
    @AppStorage("aiSelectedModel") var aiSelectedModel: String = ""
    
    // API Key 采用 Keychain 进行安全保存，对外依然暴露给 SwiftUI 作为 @Published 响应式属性
    @Published var aiApiKey: String = "" {
        didSet {
            KeychainHelper.shared.save(aiApiKey)
        }
    }
    
    private var pdfURL: URL?
    
    // 会话与任务句柄
    private var currentAISession: URLSession?
    private var currentAITask: URLSessionDataTask?
    
    // 强引用保持当前流代理，防止垃圾回收
    private var currentStreamDelegate: AIStreamDelegate?
    
    // 分片队列缓存
    private var pendingAIChunks: [String] = []
    private var aiCompletedText: String = ""    // 已拼接完成的分段结果
    private var aiLastCompletedChunkText: String = "" // 当前正在接收的分片文本缓冲
    private var systemPromptBackup: String = ""
    
    // === UI 流式回显节流 (Throttle) 属性 ===
    private var lastUIUpdateTime = Date.distantPast
    private var aiPendingOutputBuffer = ""
    
    // 专职后台磁盘 I/O 串行队列，绝不阻塞主线程 UI
    private let ioQueue = DispatchQueue(label: "com.pdfextractor.ioqueue", qos: .background)
    
    // === 线程安全 Epoch 时序 Token 锁结构 ===
    private let aiTokenLock = NSLock()
    private var _currentAIToken = UUID()
    var currentAITokenSafe: UUID {
        get {
            aiTokenLock.lock()
            defer { aiTokenLock.unlock() }
            return _currentAIToken
        }
        set {
            aiTokenLock.lock()
            _currentAIToken = newValue
            aiTokenLock.unlock()
        }
    }
    
    // 模型列表解析结构
    struct AIModelResponse: Codable {
        let data: [AIModelData]
    }
    struct AIModelData: Codable {
        let id: String
    }
    
    init() {
        // 从安全的 Keychain 中加载保存的 API Key
        // 使用 _aiApiKey 直接初始化底层 Published 存储，绕过 didSet 防止空值覆写已有凭证
        _aiApiKey = Published(initialValue: KeychainHelper.shared.read() ?? "")
        
        // 在初始化时校验已保存 API URL 的离线安全性
        let initialUrl = UserDefaults.standard.string(forKey: "aiApiBaseUrl") ?? "http://localhost:11434/v1"
        checkURLSafety(urlString: initialUrl)
    }
    
    /// 检测 API 基础地址安全性，如果配置了外网远程公网地址，向 UI 发送警告
    func checkURLSafety(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.isExternalURLWarning = false
            }
            return
        }
        
        // 提取 URL 的 host 部分用于精确匹配（同时兼容 http/https）
        guard let urlComponents = URLComponents(string: trimmed),
              let host = urlComponents.host else {
            DispatchQueue.main.async { [weak self] in
                self?.isExternalURLWarning = true
            }
            return
        }
        
        // 白名单：环回本地地址与 RFC 1918 内网网段
        var isLocal = false
        if host == "localhost" || host == "127.0.0.1" {
            isLocal = true
        } else if host.hasPrefix("192.168.") {
            isLocal = true
        } else if host.hasPrefix("10.") {
            isLocal = true
        } else if host.hasPrefix("172.") {
            // RFC 1918: 仅 172.16.0.0 ~ 172.31.255.255 属于内网私有地址
            let segments = host.split(separator: ".")
            if segments.count >= 2, let second = Int(segments[1]) {
                isLocal = (16...31).contains(second)
            }
        }
                      
        DispatchQueue.main.async { [weak self] in
            self?.isExternalURLWarning = !isLocal
        }
    }
    
    /// 拉取本地 AI 运行端点提供的可用模型列表
    func fetchAIModels() {
        // 发起请求前也跑一次安全校验
        checkURLSafety(urlString: aiApiBaseUrl)
        
        guard let url = URL(string: aiApiBaseUrl + "/models") else {
            self.updateAIProgressStatus("❌ 无效的 API 服务地址")
            return
        }
        
        isAIFetchingModels = true
        updateAIProgressStatus("正在获取模型列表...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        
        if !aiApiKey.isEmpty {
            request.addValue("Bearer \(aiApiKey)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.isAIFetchingModels = false
            }
            
            if let error = error {
                self.updateAIProgressStatus("❌ 连接失败: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                self.updateAIProgressStatus("❌ 服务器未返回数据")
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(AIModelResponse.self, from: data)
                let modelIds = decoded.data.map { $0.id }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.aiModels = modelIds
                    if !modelIds.isEmpty && (self.aiSelectedModel.isEmpty || !modelIds.contains(self.aiSelectedModel)) {
                        self.aiSelectedModel = modelIds.first ?? ""
                    }
                    self.updateAIProgressStatus("✅ 成功拉取到 \(modelIds.count) 个本地模型")
                }
            } catch {
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let dataArray = json["data"] as? [[String: Any]] {
                    let ids = dataArray.compactMap { $0["id"] as? String }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.aiModels = ids
                        if !ids.isEmpty && (self.aiSelectedModel.isEmpty || !ids.contains(self.aiSelectedModel)) {
                            self.aiSelectedModel = ids.first ?? ""
                        }
                        self.updateAIProgressStatus("✅ 成功获取 \(ids.count) 个模型")
                    }
                } else {
                    self.updateAIProgressStatus("❌ 无法解析模型列表，请确认服务是否兼容 OpenAI 规范")
                }
            }
        }.resume()
    }
    
    /// 将提取后的正文发送给本地 AI 纠错与净化 (支持超长文本智能分片串行接力)
    func processTextWithAI(inputText: String, systemPrompt: String, fileURL: URL?) {
        let cleanInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanInput.isEmpty {
            self.updateAIProgressStatus("❌ 原始提取的文本为空，请先提取文本！")
            return
        }
        
        cancelAIProcessing()
        
        self.pdfURL = fileURL
        self.isAIProcessing = true
        self.aiResultText = ""
        self.aiCompletedText = ""
        self.aiLastCompletedChunkText = ""
        self.aiTxtFileURL = nil
        self.aiMdFileURL = nil
        self.lastUIUpdateTime = Date.distantPast
        self.aiPendingOutputBuffer = ""
        
        self.systemPromptBackup = systemPrompt
        
        // 生成全新 Epoch Token，指示新一轮写入周期开始
        currentAITokenSafe = UUID()
        
        let chunks = splitTextIntoChunks(cleanInput, maxChars: 1800)
        self.pendingAIChunks = chunks
        self.aiTotalChunks = chunks.count
        self.aiCurrentChunkIndex = 0
        
        processNextChunk(systemPrompt: systemPrompt)
    }
    
    /// 串行链式处理队列中的下一个分段
    private func processNextChunk(systemPrompt: String) {
        guard isAIProcessing else { return }
        
        if pendingAIChunks.isEmpty {
            self.updateAIProgressStatus("🎉 本地 AI 净化校对完成！已自动导出文件。")
            saveAIResultToDisk()
            DispatchQueue.main.async { [weak self] in
                self?.isAIProcessing = false
            }
            return
        }
        
        checkURLSafety(urlString: aiApiBaseUrl)
        
        guard let url = URL(string: aiApiBaseUrl + "/chat/completions") else {
            self.updateAIProgressStatus("❌ 无效的 API 服务地址")
            self.isAIProcessing = false
            return
        }
        
        let chunkText = pendingAIChunks.removeFirst()
        self.aiLastCompletedChunkText = ""
        self.aiPendingOutputBuffer = ""
        
        updateAIProgressStatus("本地 AI 正在推理第 \(aiCurrentChunkIndex + 1) / \(aiTotalChunks) 段...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600.0
        
        if !aiApiKey.isEmpty {
            request.addValue("Bearer \(aiApiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let strictSystemPrompt = systemPrompt + "\n【极其重要】：此输入是整篇长文本中的一小段。为了实现多段无缝拼接，您只需直接输出这一段净化排版后的纯正文内容，严禁夹带任何引导语、总结性废话。同时，您必须严格保留原本存在的自然段落结构与所有换行，切勿将它们强行合并或压缩为一大段！直接输出本段处理后的文字！"
        
        let messages: [[String: String]] = [
            ["role": "system", "content": strictSystemPrompt],
            ["role": "user", "content": chunkText]
        ]
        
        let requestBody: [String: Any] = [
            "model": aiSelectedModel.isEmpty ? "default" : aiSelectedModel,
            "messages": messages,
            "temperature": 0.1,
            "stream": true
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            self.updateAIProgressStatus("❌ 序列化请求数据失败")
            self.isAIProcessing = false
            return
        }
        
        // 实例化解耦后的流代理，并在闭包中接收回传
        let streamDelegate = AIStreamDelegate()
        streamDelegate.onDeltaReceived = { [weak self] content in
            self?.appendDeltaText(content)
        }
        streamDelegate.onComplete = { [weak self] error in
            self?.handleChunkComplete(error: error)
        }
        self.currentStreamDelegate = streamDelegate
        
        let session = URLSession(configuration: .default, delegate: streamDelegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        
        self.currentAISession = session
        self.currentAITask = task
        task.resume()
    }
    
    /// 处理单片分片传输完毕后的接力和落盘逻辑
    private func handleChunkComplete(error: Error?) {
        // 在 delegate 网络回调线程中，必须安全分发到主线程，避免 Data Race 崩溃
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 如果任务已被 cancel 清理，直接丢弃残余回调
            guard self.isAIProcessing else { return }
            
            // 强力冲刷未写入界面的残留缓冲
            self.flushPendingAIText()
            
            self.currentAITask = nil
            self.currentAISession?.finishTasksAndInvalidate()
            self.currentAISession = nil
            self.currentStreamDelegate = nil // 断开强引用
            
            if let error = error as NSError? {
                if error.code == NSURLErrorCancelled {
                    return
                }
                self.updateAIProgressStatus("❌ 优化生成中断: \(error.localizedDescription)")
                self.isAIProcessing = false
            } else {
                self.aiCompletedText += self.aiLastCompletedChunkText + "\n\n"
                
                // 将文件写入异步派发至后台 I/O 线程，解决 UI 发生卡顿
                let chunkToSave = self.aiLastCompletedChunkText
                let chunkIdx = self.aiCurrentChunkIndex
                self.appendAIResultChunkToDisk(chunkContent: chunkToSave, chunkIndex: chunkIdx)
                
                self.aiCurrentChunkIndex += 1
                self.processNextChunk(systemPrompt: self.systemPromptBackup)
            }
        }
    }
    
    /// 中止 AI 文本润色进程
    func cancelAIProcessing() {
        // 强制递增时序 Token。所有已经在 ioQueue 线程中排队挂起的写盘任务，其持有的旧 Token 均将失效
        currentAITokenSafe = UUID()
        
        // 确保所有 @Published 属性修改在主线程执行，防止非主线程调用时的 Data Race 崩溃
        let cleanup = { [weak self] in
            guard let self = self else { return }
            self.pendingAIChunks.removeAll()
            self.aiPendingOutputBuffer = ""
            
            if let task = self.currentAITask {
                task.cancel()
                self.currentAITask = nil
                
                self.currentAISession?.invalidateAndCancel()
                self.currentAISession = nil
                self.currentStreamDelegate = nil
                
                self.isAIProcessing = false
                self.aiTxtFileURL = nil
                self.aiMdFileURL = nil
                self.updateAIProgressStatus("❌ 已主动取消 AI 优化净化流程。")
            }
        }
        
        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }
    }
    
    private func updateAIProgressStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.aiProgressStatus = status
        }
    }
    
    /// 节流刷新：强制分发到主线程，杜绝多线程读写 aiPendingOutputBuffer 导致崩溃 (Data Race Fix)
    private func appendDeltaText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.aiPendingOutputBuffer += text
            let now = Date()
            if now.timeIntervalSince(self.lastUIUpdateTime) > 0.1 {
                self.flushPendingAIText()
                self.lastUIUpdateTime = now
            }
        }
    }
    
    /// 强制冲刷增量字符缓冲区到 UI (必须在主线程中运行)
    private func flushPendingAIText() {
        guard !aiPendingOutputBuffer.isEmpty else { return }
        let textToAppend = aiPendingOutputBuffer
        aiPendingOutputBuffer = ""
        
        self.aiLastCompletedChunkText += textToAppend
        self.aiResultText = self.aiCompletedText + self.aiLastCompletedChunkText
    }
    
    /// 【退避断句切分算法】：排版与分片重叠度智能预处理
    private func splitTextIntoChunks(_ text: String, maxChars: Int = 1800) -> [String] {
        var chunks: [String] = []
        var remainingText = text
        
        while !remainingText.isEmpty {
            if remainingText.count <= maxChars {
                chunks.append(remainingText)
                break
            }
            
            let subrange = remainingText.prefix(maxChars)
            let searchMinIndex = max(1000, maxChars - 400)
            let searchArea = String(subrange.suffix(maxChars - searchMinIndex))
            
            var cutOffset = -1
            
            if let lastNewLineIndex = searchArea.lastIndex(of: "\n") {
                cutOffset = searchMinIndex + searchArea.distance(from: searchArea.startIndex, to: lastNewLineIndex)
            } else {
                let punctuation: [Character] = ["。", "！", "？", "；", ".", "!", "?", ";"]
                var latestPunctIndex: String.Index? = nil
                for char in punctuation {
                    if let index = searchArea.lastIndex(of: char) {
                        if latestPunctIndex == nil || index > latestPunctIndex! {
                            latestPunctIndex = index
                        }
                    }
                }
                
                if let idx = latestPunctIndex {
                    cutOffset = searchMinIndex + searchArea.distance(from: searchArea.startIndex, to: idx) + 1
                } else {
                    let minorPunct: [Character] = ["，", "、", ","]
                    var latestMinorIndex: String.Index? = nil
                    for char in minorPunct {
                        if let index = searchArea.lastIndex(of: char) {
                            if latestMinorIndex == nil || index > latestMinorIndex! {
                                latestMinorIndex = index
                            }
                        }
                    }
                    if let idx = latestMinorIndex {
                        cutOffset = searchMinIndex + searchArea.distance(from: searchArea.startIndex, to: idx) + 1
                    }
                }
            }
            
            if cutOffset == -1 {
                cutOffset = maxChars
            }
            
            let cutIndex = remainingText.index(remainingText.startIndex, offsetBy: cutOffset)
            let chunk = String(remainingText[..<cutIndex])
            chunks.append(chunk)
            
            remainingText = String(remainingText[cutIndex...])
        }
        
        return chunks
    }
    
    /// 将 AI 纠正的成果异步写盘 (由 ioQueue 执行)
    private func saveAIResultToDisk() {
        guard let url = pdfURL, !aiResultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let baseName = url.deletingPathExtension().lastPathComponent
        let aiTxtURL = url.deletingLastPathComponent().appendingPathComponent(baseName + "_AI净化").appendingPathExtension("txt")
        let aiMdURL = url.deletingLastPathComponent().appendingPathComponent(baseName + "_AI净化").appendingPathExtension("md")
        
        let finalResultText = aiResultText // 获取快照，安全传给子线程
        let token = self.currentAITokenSafe // 捕获当前 Epoch
        
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            // 写入前安全比对 Epoch Token
            guard self.currentAITokenSafe == token else { return }
            
            do {
                try finalResultText.write(to: aiTxtURL, atomically: true, encoding: .utf8)
                
                // 为 Markdown 添加标题
                let mdContent = "# \(baseName) AI 净化校对正文\n\n\(finalResultText)"
                try mdContent.write(to: aiMdURL, atomically: true, encoding: .utf8)
                
                self.updateAIProgressStatus("✅ 本地 AI 净化校对完成！已自动导出文件。")
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.aiTxtFileURL = aiTxtURL
                    self.aiMdFileURL = aiMdURL
                }
            } catch {
                self.updateAIProgressStatus("❌ 本地 AI 净化已完成，但自动写入硬盘失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 分片落盘：在每分片完成时在 ioQueue 中追加写盘，彻底规避主线程 IO，应用 Epoch Token 隔离
    private func appendAIResultChunkToDisk(chunkContent: String, chunkIndex: Int) {
        guard let url = pdfURL, !chunkContent.isEmpty else { return }
        
        let baseName = url.deletingPathExtension().lastPathComponent
        let aiTxtURL = url.deletingLastPathComponent().appendingPathComponent(baseName + "_AI净化").appendingPathExtension("txt")
        let aiMdURL = url.deletingLastPathComponent().appendingPathComponent(baseName + "_AI净化").appendingPathExtension("md")
        
        let token = self.currentAITokenSafe // 捕获当前 Epoch
        
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            // 检查 Token 确定本任务在此 Epoch 周期内依然有效。若已取消重来，丢弃本次写入，防止前代数据污染新提取文档。
            guard self.currentAITokenSafe == token else {
                print("[AI写入提示] 丢弃前代残留分片的磁盘写入操作。")
                return
            }
            
            do {
                if chunkIndex == 0 {
                    try "".write(to: aiTxtURL, atomically: true, encoding: .utf8)
                    let mdTitle = "# \(baseName) AI 净化校对正文\n\n"
                    try mdTitle.write(to: aiMdURL, atomically: true, encoding: .utf8)
                }
                
                if !FileManager.default.fileExists(atPath: aiTxtURL.path) {
                    try "".write(to: aiTxtURL, atomically: true, encoding: .utf8)
                }
                let fileHandle = try FileHandle(forWritingTo: aiTxtURL)
                try fileHandle.seekToEnd()
                let appendDataStr = chunkContent + "\n\n"
                if let writeData = appendDataStr.data(using: .utf8) {
                    try fileHandle.write(contentsOf: writeData)
                }
                try fileHandle.close()
                
                if !FileManager.default.fileExists(atPath: aiMdURL.path) {
                    let mdTitle = "# \(baseName) AI 净化校对正文\n\n"
                    try mdTitle.write(to: aiMdURL, atomically: true, encoding: .utf8)
                }
                let fileHandleMd = try FileHandle(forWritingTo: aiMdURL)
                try fileHandleMd.seekToEnd()
                
                let mdAppendStr = "## 优化分段 \(chunkIndex + 1)\n\n" + chunkContent + "\n\n"
                if let writeDataMd = mdAppendStr.data(using: .utf8) {
                    try fileHandleMd.write(contentsOf: writeDataMd)
                }
                try fileHandleMd.close()
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.aiTxtFileURL = aiTxtURL
                    self.aiMdFileURL = aiMdURL
                }
            } catch {
                print("分片磁盘追加失败: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 独立的 URLSessionDataDelegate 流代理，解耦 NSObject 混合继承 (1.3 节整改要求)
final class AIStreamDelegate: NSObject, URLSessionDataDelegate {
    private var streamBuffer = Data()
    
    var onDeltaReceived: ((String) -> Void)?
    var onComplete: ((Error?) -> Void)?
    
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        streamBuffer.append(data)
        
        while let lineEndIndex = streamBuffer.firstIndex(of: 10) {
            let lineData = streamBuffer.subdata(in: 0..<lineEndIndex)
            streamBuffer.removeSubrange(0...lineEndIndex)
            
            guard let lineStr = String(data: lineData, encoding: .utf8) else { continue }
            let trimmed = lineStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            var jsonPart = trimmed
            if trimmed.hasPrefix("data: ") {
                jsonPart = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if jsonPart == "[DONE]" {
                continue
            }
            
            if let content = parseDeltaContent(from: jsonPart) {
                onDeltaReceived?(content)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete?(error)
    }
    
    private func parseDeltaContent(from jsonStr: String) -> String? {
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }
}
