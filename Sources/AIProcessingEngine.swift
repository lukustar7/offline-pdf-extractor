import SwiftUI

// MARK: - 本地 AI 净化服务引擎 (纯 Swift 类解耦版)
class AIProcessingEngine: ObservableObject {
    @Published var isAIProcessing = false
    @Published var aiProgressStatus: String = ""
    @Published var aiResultText: String = ""
    @Published var aiTxtFileURL: URL?
    @Published var aiMdFileURL: URL?
    
    // === 物理页码对应的 AI 优化文本缓存 ===
    @Published var aiPagesText: [Int: String] = [:]
    
    // 当前正在处理的物理页队列缓存
    private var pendingPagesToProcess: [(pageIndex: Int, text: String)] = []
    
    // 当前正在流式输出的目标物理页码
    private var currentPageIndexProcessing: Int?
    
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
    /// 本地 AI 净化校对主入口（现在改为完全以 PDF 物理页码为核心进行分段）
    func processTextWithAI(
        extractedPages: [Int: String],
        targetPages: [Int],
        systemPrompt: String,
        fileURL: URL?
    ) {
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
        currentAITokenSafe = UUID()
        
        // 提取需要处理的非空物理页
        var chunks: [(pageIndex: Int, text: String)] = []
        for page in targetPages.sorted() {
            if let text = extractedPages[page], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append((pageIndex: page, text: text))
            }
        }
        
        if chunks.isEmpty {
            self.updateAIProgressStatus("❌ 目标页面中没有需要净化的文本内容，请先提取文本。")
            self.isAIProcessing = false
            return
        }
        
        self.pendingPagesToProcess = chunks
        self.aiTotalChunks = chunks.count
        self.aiCurrentChunkIndex = 0
        
        // 初始化目标页的缓存
        for chunk in chunks {
            self.aiPagesText[chunk.pageIndex] = ""
        }
        
        processNextPageChunk(systemPrompt: systemPrompt)
    }
    
    /// 串行链式处理队列中的下一个物理页
    private func processNextPageChunk(systemPrompt: String) {
        guard isAIProcessing else { return }
        
        if pendingPagesToProcess.isEmpty {
            self.updateAIProgressStatus("🎉 本地 AI 净化校对完成！")
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
        
        let next = pendingPagesToProcess.removeFirst()
        self.currentPageIndexProcessing = next.pageIndex
        self.aiLastCompletedChunkText = ""
        self.aiPendingOutputBuffer = ""
        
        updateAIProgressStatus("本地 AI 正在净化第 \(next.pageIndex) 页 (进度: \(aiCurrentChunkIndex + 1) / \(aiTotalChunks) 页)...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600.0
        
        if !aiApiKey.isEmpty {
            request.addValue("Bearer \(aiApiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let strictSystemPrompt = systemPrompt + "\n【极其重要】：当前输入是 PDF 中的第 \(next.pageIndex) 页正文内容。请根据系统指示进行水印过滤与语义还原，只输出净化排版后的纯正文，严禁输出任何引导语、修辞废话或总结。请务必保持原有的自然段落与换行格式！直接输出本页文字！"
        
        let messages: [[String: String]] = [
            ["role": "system", "content": strictSystemPrompt],
            ["role": "user", "content": next.text]
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
        
        let streamDelegate = AIStreamDelegate()
        streamDelegate.onDeltaReceived = { [weak self] content in
            self?.appendDeltaText(content)
        }
        streamDelegate.onComplete = { [weak self] error in
            self?.handlePageChunkComplete(error: error)
        }
        self.currentStreamDelegate = streamDelegate
        
        let session = URLSession(configuration: .default, delegate: streamDelegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        
        self.currentAISession = session
        self.currentAITask = task
        task.resume()
    }
    
    /// 处理单页传输完毕后的接力和落盘逻辑
    private func handlePageChunkComplete(error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.isAIProcessing else { return }
            
            self.flushPendingAIText()
            
            self.currentAITask = nil
            self.currentAISession?.finishTasksAndInvalidate()
            self.currentAISession = nil
            self.currentStreamDelegate = nil
            
            if let error = error as NSError? {
                if error.code == NSURLErrorCancelled {
                    return
                }
                self.updateAIProgressStatus("❌ 优化生成中断: \(error.localizedDescription)")
                self.isAIProcessing = false
            } else {
                // 每页处理完后，我们把这页的最终结果 aiLastCompletedChunkText 写回 aiPagesText
                if let pageIdx = self.currentPageIndexProcessing {
                    self.aiPagesText[pageIdx] = self.aiLastCompletedChunkText
                }
                
                // 将 memory 文本拼接，方便导出
                let pageHeader = "\n[第 \(self.currentPageIndexProcessing ?? 0) 页]\n"
                self.aiCompletedText += pageHeader + self.aiLastCompletedChunkText + "\n"
                
                let chunkToSave = self.aiLastCompletedChunkText
                let chunkIdx = self.aiCurrentChunkIndex
                self.appendAIResultChunkToDisk(chunkContent: chunkToSave, chunkIndex: chunkIdx)
                
                self.aiCurrentChunkIndex += 1
                self.currentPageIndexProcessing = nil
                self.processNextPageChunk(systemPrompt: self.systemPromptBackup)
            }
        }
    }
    
    /// 中止 AI 文本润色进程 (保留已经吐出来的和已完成物理页的内容)
    func cancelAIProcessing() {
        // 强制递增时序 Token。所有已经在 ioQueue 线程中排队挂起的写盘任务，其持有的旧 Token 均将失效
        currentAITokenSafe = UUID()
        
        // 确保所有 @Published 属性修改在主线程执行，防止非主线程调用时的 Data Race 崩溃
        let cleanup = { [weak self] in
            guard let self = self else { return }
            self.pendingAIChunks.removeAll()
            self.pendingPagesToProcess.removeAll()
            self.currentPageIndexProcessing = nil
            self.aiPendingOutputBuffer = ""
            
            if let task = self.currentAITask {
                task.cancel()
                self.currentAITask = nil
            }
            
            self.currentAISession?.invalidateAndCancel()
            self.currentAISession = nil
            self.currentStreamDelegate = nil
            
            self.isAIProcessing = false
            self.aiTxtFileURL = nil
            self.aiMdFileURL = nil
            self.updateAIProgressStatus("❌ 已主动取消 AI 优化净化流程。")
        }
        
        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }
    }
    
    /// 彻底清除所有已保存的 AI 页码缓存与导出文件路径 (当关闭 PDF 文件时调用)
    func clear() {
        cancelAIProcessing()
        let mainClear = { [weak self] in
            guard let self = self else { return }
            self.aiPagesText = [:]
            self.aiResultText = ""
            self.aiCompletedText = ""
        }
        if Thread.isMainThread {
            mainClear()
        } else {
            DispatchQueue.main.async(execute: mainClear)
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
        
        // 同步更新当前正在处理的物理页的 AI 净化文本缓存
        if let pageIdx = currentPageIndexProcessing {
            self.aiPagesText[pageIdx] = (self.aiPagesText[pageIdx] ?? "") + textToAppend
        }
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
    
    private func saveAIResultToDisk() {
        // 取消后台自动存盘，全部由用户在界面上点击导出按钮手动另存
    }
    
    private func appendAIResultChunkToDisk(chunkContent: String, chunkIndex: Int) {
        // 取消后台自动追加分片落盘，数据纯在内存中保存
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
