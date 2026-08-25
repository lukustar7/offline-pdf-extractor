# PDF 本地文字提取工具

macOS 原生 PDF 文字提取与去水印工具。PDF 解析、Core Image 图像预处理、Vision OCR 和文本导出均在本机完成；AI 净化默认连接本地 OpenAI 兼容端点。

## 功能

- 电子文本 PDF：读取文本层，仅删除用户确认的整行水印词。
- 扫描 PDF：支持 Core Image 图像色阶拉伸消除浅灰/半透明背景水印与彩色印章，并使用 macOS Vision OCR 进行文字识别。
- 水印处理：检测前 30 页高频文本，候选词默认不勾选；支持手动过滤词、可选 OCR 前遮罩与去水印前后分屏对比。
- AI 净化：支持 Ollama、LM Studio 与其他 OpenAI 兼容端点，按物理页串行处理并提供单页失败容错。
- 结果检查：支持 Markdown 富文本渲染与纯文本双模切换、一键复制当前页、TXT 和 Markdown 导出。
- 界面架构：遵循 Apple HIG 原生规范，包含首次启动欢迎页、待机导入页、页面缩略图侧栏、物理纸张主画布、0 滚屏检查器与独立设置窗口 (⌘,)。

## PDF 场景

1. 电子文本 + 电子水印：读取文本层，不执行 OCR。
2. 扫描正文 + 电子水印：保留扫描图像执行 OCR，遮罩仅作为手动选项。
3. 全扫描件：整页经 Core Image 图像去水印预处理后执行 OCR，重叠内容可继续使用 AI 净化。

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

- `PDFExtractorEngine`：文件、任务、页面导航和缩略图状态。
- `PDFExtractionWorker`：后台 PDFKit 渲染、Core Image 去水印滤镜、缩略图生成与 Vision OCR。
- `AIProcessingEngine`：端点、模型、凭证、流式任务生命周期与单页容错调度。
- `PageRangeParser`、`AIEndpoint`、`OpenAIStreamParser`：可独立测试的纯逻辑模块。
- `SidebarThumbnailView`、`PDFCanvasView`、`ResultInspectorView`、`SettingsView`、`WelcomeView`、`LaunchView`：原生用户界面组件。
