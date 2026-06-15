import SwiftUI

// MARK: - 本地 AI 净化服务引擎
class AIProcessingEngine: NSObject, ObservableObject {
    @Published var isAIProcessing = false
    @Published var aiProgressStatus: String = ""
    @Published var aiResultText: String = ""
    @Published var aiTxtFileURL: URL?
    
    @Published var aiModels: [String] = []
    @Published var isAIFetchingModels = false
    
    // === 本地 AI 串行分片推理进度 ===
    @Published var aiTotalChunks: Int = 0       // 总分段数
    @Published var aiCurrentChunkIndex: Int = 0 // 当前分段索引 (0-indexed)
    
    // 使用 @AppStorage 自动将关键设置持久化到本地 UserDefaults 中
    @AppStorage("aiApiBaseUrl") var aiApiBaseUrl: String = "http://localhost:11434/v1"
    @AppStorage("aiApiKey") var aiApiKey: String = ""
    @AppStorage("aiSelectedModel") var aiSelectedModel: String = ""
    
    private var pdfURL: URL?
    
    // 会话与任务句柄
    private var currentAISession: URLSession?
    private var currentAITask: URLSessionDataTask?
    
    // TCP 数据包缓冲与解析
    private var streamBuffer = Data()
    
    // 分片队列缓存
    private var pendingAIChunks: [String] = []
    private var aiCompletedText: String = ""    // 已拼接完成的分段结果
    private var aiLastCompletedChunkText: String = "" // 当前正在接收的分片文本缓冲
    private var systemPromptBackup: String = ""
    
    // === UI 流式回显节流 (Throttle) 属性 ===
    private var lastUIUpdateTime = Date.distantPast
    private var aiPendingOutputBuffer = ""
    
    // 模型列表解析结构
    struct AIModelResponse: Codable {
        let data: [AIModelData]
    }
    struct AIModelData: Codable {
        let id: String
    }
    
    override init() {
        super.init()
    }
    
    /// 拉取本地 AI 运行端点提供的可用模型列表
    func fetchAIModels() {
        guard let url = URL(string: aiApiBaseUrl + "/models") else {
            self.updateAIProgressStatus("❌ 无效的 API 服务地址")
            return
        }
        
        isAIFetchingModels = true
        updateAIProgressStatus("正在获取模型列表...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0 // 本地加载允许 15 秒超时
        
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
                        self.aiSelectedModel = modelIds.first!
                    }
                    self.updateAIProgressStatus("✅ 成功拉取到 \(modelIds.count) 个本地模型")
                }
            } catch {
                // 兼容非标 JSON 响应格式 (例如 LM Studio 或某些 Ollama 直出)
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let dataArray = json["data"] as? [[String: Any]] {
                    let ids = dataArray.compactMap { $0["id"] as? String }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.aiModels = ids
                        if !ids.isEmpty && (self.aiSelectedModel.isEmpty || !ids.contains(self.aiSelectedModel)) {
                            self.aiSelectedModel = ids.first!
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
        
        // 中断之前可能存在的残留推理会话
        cancelAIProcessing()
        
        self.pdfURL = fileURL
        self.isAIProcessing = true
        self.aiResultText = ""
        self.aiCompletedText = ""
        self.aiLastCompletedChunkText = ""
        self.streamBuffer = Data()
        self.aiTxtFileURL = nil
        self.lastUIUpdateTime = Date.distantPast
        self.aiPendingOutputBuffer = ""
        
        self.systemPromptBackup = systemPrompt
        
        // 对文本按最大 1800 字符进行智能断句切片
        let chunks = splitTextIntoChunks(cleanInput, maxChars: 1800)
        self.pendingAIChunks = chunks
        self.aiTotalChunks = chunks.count
        self.aiCurrentChunkIndex = 0
        
        // 触发首个分段推理
        processNextChunk(systemPrompt: systemPrompt)
    }
    
    /// 串行链式处理队列中的下一个分段
    private func processNextChunk(systemPrompt: String) {
        guard isAIProcessing else { return }
        
        // 队列全部消费完毕，做最终存盘收尾
        if pendingAIChunks.isEmpty {
            self.updateAIProgressStatus("🎉 本地 AI 净化校对完成！已自动导出文件。")
            saveAIResultToDisk()
            DispatchQueue.main.async { [weak self] in
                self?.isAIProcessing = false
            }
            return
        }
        
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
        request.timeoutInterval = 86400.0 // 允许超长推理响应时间
        
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
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        
        self.currentAISession = session
        self.currentAITask = task
        task.resume()
    }
    
    /// 中止 AI 文本润色进程
    func cancelAIProcessing() {
        streamBuffer = Data()
        pendingAIChunks.removeAll()
        aiPendingOutputBuffer = ""
        
        if let task = currentAITask {
            task.cancel()
            currentAITask = nil
            
            currentAISession?.invalidateAndCancel()
            currentAISession = nil
            
            isAIProcessing = false
            updateAIProgressStatus("❌ 已主动取消 AI 优化净化流程。")
        }
    }
    
    private func updateAIProgressStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.aiProgressStatus = status
        }
    }
    
    /// 节流刷新：将网络字符追加入待更新缓存中，限频刷新 UI
    private func appendDeltaText(_ text: String) {
        aiPendingOutputBuffer += text
        let now = Date()
        // 超过 100ms 的时间间隔才发起一次 SwiftUI UI 更新，彻底防止 CPU 渲染风暴卡死
        if now.timeIntervalSince(lastUIUpdateTime) > 0.1 {
            flushPendingAIText()
            lastUIUpdateTime = now
        }
    }
    
    /// 强制冲刷增量字符缓冲区到 UI
    private func flushPendingAIText() {
        guard !aiPendingOutputBuffer.isEmpty else { return }
        let textToAppend = aiPendingOutputBuffer
        aiPendingOutputBuffer = ""
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.aiLastCompletedChunkText += textToAppend
            self.aiResultText = self.aiCompletedText + self.aiLastCompletedChunkText
        }
    }
    
    /// 【退避断句切分算法】：确保句子或段落的完整，同时有硬切边界
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
            
            // 优先退避段落换行
            if let lastNewLineIndex = searchArea.lastIndex(of: "\n") {
                cutOffset = searchMinIndex + searchArea.distance(from: searchArea.startIndex, to: lastNewLineIndex)
            }
            // 其次句终标点
            else {
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
                }
                // 再次逗号等中顿标点
                else {
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
            
            // 兜底硬切
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
    
    /// 将 AI 纠正的成果全量写盘
    private func saveAIResultToDisk() {
        guard let url = pdfURL, !aiResultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let baseName = url.deletingPathExtension().lastPathComponent
        let aiTxtURL = url.deletingLastPathComponent().appendingPathComponent(baseName + "_AI净化").appendingPathExtension("txt")
        
        do {
            try aiResultText.write(to: aiTxtURL, atomically: true, encoding: .utf8)
            self.updateAIProgressStatus("✅ 本地 AI 净化校对完成！已自动导出文件。")
            
            DispatchQueue.main.async { [weak self] in
                self?.aiTxtFileURL = aiTxtURL
            }
        } catch {
            self.updateAIProgressStatus("❌ 本地 AI 净化已完成，但自动写入硬盘失败: \(error.localizedDescription)")
        }
    }
    
    /// 分片落盘：在每分片完成时追加写盘
    private func appendAIResultChunkToDisk(chunkContent: String) {
        guard let url = pdfURL, !chunkContent.isEmpty else { return }
        
        let baseName = url.deletingPathExtension().lastPathComponent
        let aiTxtURL = url.deletingLastPathComponent().appendingPathComponent(baseName + "_AI净化").appendingPathExtension("txt")
        
        do {
            if aiCurrentChunkIndex == 0 {
                try "".write(to: aiTxtURL, atomically: true, encoding: .utf8)
            }
            
            if !FileManager.default.fileExists(atPath: aiTxtURL.path) {
                try "".write(to: aiTxtURL, atomically: true, encoding: .utf8)
            }
            
            let fileHandle = try FileHandle(forWritingTo: aiTxtURL)
            try fileHandle.seekToEnd()
            
            // 分片以双换行隔离
            let appendDataStr = chunkContent + "\n\n"
            if let writeData = appendDataStr.data(using: .utf8) {
                try fileHandle.write(contentsOf: writeData)
            }
            try fileHandle.close()
            
            DispatchQueue.main.async { [weak self] in
                self?.aiTxtFileURL = aiTxtURL
            }
        } catch {
            print("分片磁盘追加失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - URLSessionDataDelegate 实现 (流式网络处理)
extension AIProcessingEngine: URLSessionDataDelegate {
    
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
                // 将接收到的字符塞入待合并节流刷新区
                appendDeltaText(content)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 强制把残余缓冲区的字符刷出来
        flushPendingAIText()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.streamBuffer = Data()
            self.currentAITask = nil
            self.currentAISession?.invalidateAndCancel()
            self.currentAISession = nil
            
            if let error = error as NSError? {
                if error.code == NSURLErrorCancelled {
                    return
                }
                self.updateAIProgressStatus("❌ 优化生成中断: \(error.localizedDescription)")
                self.isAIProcessing = false
            } else {
                // 本段完成，开始接力
                self.aiCompletedText += self.aiLastCompletedChunkText + "\n\n"
                self.appendAIResultChunkToDisk(chunkContent: self.aiLastCompletedChunkText)
                
                self.aiCurrentChunkIndex += 1
                self.processNextChunk(systemPrompt: self.systemPromptBackup)
            }
        }
    }
}
