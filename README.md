# PDF 本地文字提取工具

macOS 原生 PDF 文字提取与去水印工具。PDF 解析、Vision OCR 和文本导出均在本机完成；AI 净化默认连接本地 OpenAI 兼容端点。

## 功能

- 电子文本 PDF：读取文本层，仅删除用户确认的整行水印词。
- 扫描 PDF：使用 macOS Vision OCR，单页图像缓冲上限约 64 MiB。
- 水印处理：检测前 30 页高频文本，候选词默认不勾选；支持手动过滤词和可选 OCR 前遮罩。
- AI 净化：支持 Ollama、LM Studio 与其他 OpenAI 兼容端点，按物理页串行处理。
- 结果检查：PDF、原文与 AI 结果共用页码，支持 TXT 和 Markdown 导出。

## PDF 场景

1. 电子文本 + 电子水印：读取文本层，不执行 OCR。
2. 扫描正文 + 电子水印：保留扫描图像执行 OCR，遮罩仅作为手动选项。
3. 全扫描件：整页 OCR 后过滤水印残留，重叠内容可继续使用 AI 净化。

## 安全边界

- API 密钥仅在用户确认后写入 macOS 钥匙串。
- 外部 AI 地址必须逐地址授权；地址变化后授权自动失效。
- 公网 HTTP 地址禁止携带 API 密钥，所有 AI 网络重定向均被阻止。
- AI 流式单行缓冲限制为 1 MiB，HTTP 错误正文限制为 64 KiB。

## 环境

- macOS 14.0 或更高版本
- Swift 6 Command Line Tools 或完整 Xcode（仅源码构建需要）
- Ollama、LM Studio 或兼容服务（仅 AI 净化需要）

## 运行

直接打开项目根目录的 `PDF文字提取.app`。

## 验证与构建

```bash
./test.sh
./build.sh
```

`test.sh` 执行 16 项零依赖核心逻辑测试。`build.sh` 会再次运行测试，随后生成当前 Mac 处理器架构的 Release App，执行本地签名并校验最低系统版本。

## 结构

- `PDFExtractorEngine`：文件、任务和界面状态。
- `PDFExtractionWorker`：后台 PDFKit 渲染、过滤与 Vision OCR。
- `AIProcessingEngine`：端点、模型、凭证和流式任务生命周期。
- `PageRangeParser`、`AIEndpoint`、`OpenAIStreamParser`：可独立测试的纯逻辑模块。
