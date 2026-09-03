# PDF 本地文字提取工具

macOS 原生 PDF 文字提取与去水印工具。PDF 解析、Core Image 图像预处理、Vision OCR 和文本导出均在本机完成；AI 净化默认连接本地 OpenAI 兼容端点。

## 功能

- 智能通道探测：导入时自动抽样探测矢量文本层，自动匹配极速文本层提取或 Vision OCR 通道。
- 离线段落重构：基于标点符号与上下文结构分析，自动合并生硬换行，消除碎回车，并保护标题与编号列表。
- 科学去印与水印处理：通过红通道投影消除红色公章，结合色阶拉伸消除浅灰水印；自动分析高频电子水印词并提供按需勾选与手动词库。
- 沉浸式文本工作室：提供“当前页对照”与“全篇大纲”双重视图，参数收纳为可折叠抽屉，释放全高度阅读空间，支持单页与全篇一键复制及多格式导出。
- 本地 AI 净化：支持 Ollama、LM Studio 与其他兼容端点，按物理页串行处理并提供单页失败容错，支持 Markdown 渲染与源码双模切换。
- 原生交互体验：遵循 Apple HIG 原生规范，支持纵向连续顺滑滚动阅读、页面缩略图侧栏与独立设置窗口 (⌘,)。

## PDF 场景

1. 电子文本 + 电子水印：读取矢量文本层，执行离线段落重构，仅过滤确认的水印词。
2. 扫描正文 + 电子水印：保留扫描图像执行 OCR，过滤水印并重构自然段落。
3. 全扫描件：整页经红通道投影与色阶拉伸去印预处理后执行 OCR，支持去水印前后分屏对比。

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

`test.sh` 执行 19 项零依赖核心逻辑测试。`build.sh` 会再次运行测试，随后生成当前 Mac 处理器架构的 Release App，执行本地签名并校验最低系统版本。

## 结构

- `PDFExtractorEngine`：文件生命周期、任务控制、页面导航与缩略图状态管理。
- `PDFExtractionWorker`：后台 PDFKit 渲染、Core Image 通道去印与去水印滤镜、缩略图生成与 Vision OCR。
- `ParagraphReconstructor`：启发式离线段落重构引擎，负责断句合并与排版结构保护。
- `AIProcessingEngine`：端点、模型、凭证、流式任务生命周期与单页容错调度。
- `PageRangeParser`、`AIEndpoint`、`OpenAIStreamParser`：可独立测试的纯逻辑模块。
- `SidebarThumbnailView`、`PDFCanvasView`、`ResultInspectorView`、`SettingsView`、`WelcomeView`、`LaunchView`：原生用户界面组件。
