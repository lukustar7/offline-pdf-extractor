# PDF 本地文字提取工具

macOS 原生 PDF 图文提取与去水印工具。PDF 解析、Core Image 图像预处理、Vision OCR、插图定位截取与 Word (.docx) 导出均在本机纯离线完成。

## 功能

- 智能通道探测：导入时自动抽样探测矢量文本层，自动匹配极速文本层提取或 Vision OCR 通道。
- 图文与插图完整留存：自动定位并截取 PDF 电子版及扫描件中的图表与插图，按阅读顺序自然插入段落之间。
- 统一 Word (.docx) 导出：原生生成标准 Office Open XML 格式，单一文件无损内嵌全部插图与段落样式，双击开箱即用；同时支持 Markdown 导出。
- 离线段落重构：基于标点符号与上下文结构分析，自动合并生硬换行，消除碎回车，并保护标题与编号列表。
- 科学去印与水印处理：通过红通道投影消除红色公章，结合色阶拉伸消除浅灰水印；自动分析高频电子水印词并提供按需勾选与手动词库。
- 图文工作室交互：遵循 Apple HIG 原生规范，采用开阔三栏工作台与 36px/38px 标准大气控件，支持纵向连续顺滑阅读、页面缩略图侧栏与独立偏好设置窗口 (⌘,)。

## PDF 场景

1. 可选文字 + 文字水印：适合可选中复制文字的常规电子 PDF，读取文本层与内嵌原图，1秒极速提取并完整保留排版。
2. 扫描正文 + 文字水印：适合正文为不可选图像但水印为后加文字的扫描件，自动滤除文字水印后通过 Vision OCR 识别文字并截取插图。
3. 扫描正文 + 纸印水印：适合正文与水印印章均打印在纸上的一体化扫描件，自动执行背景与印章净化预处理后再识别。

## 安全边界

- 100% 纯本地离线运行，应用未声明任何网络连接权限，不请求任何外部服务。
- 所有文本识别、图像分析与 Word 文档构建均在本地处理器完成，数据永不出设备。

## 环境

- macOS 14.0 或更高版本
- Apple Silicon (M 系列芯片，ARM64 纯血架构，不支持 Intel)
- Swift 6 Command Line Tools 或完整 Xcode（仅源码构建需要）

## 运行

直接打开项目根目录的 `PDF文字提取.app`。

## 验证、构建与瘦身

```bash
./test.sh
./build.sh
./clean.sh
```

`test.sh` 执行 19 项零依赖核心逻辑与大文件压力测试。`build.sh` 会再次运行测试，随后针对 Apple Silicon (ARM64) 编译生成 Release App，执行本地签名并校验最低系统版本。`clean.sh` 可一键清理编译缓存，随时释放磁盘空间。

## 结构

- `PDFExtractorEngine`：文件生命周期、任务控制、页面导航、缩略图状态与 Word/Markdown 导出调度。
- `PDFExtractionWorker`：后台 PDFKit 渲染、Core Image 通道去印与去水印滤镜、缩略图生成与 Vision OCR。
- `DocumentLayoutAnalyzer`：版面自适应插图外接矩形探测、文字网格遮蔽与纵向图文混排算法。
- `DocxDocumentBuilder`：macOS 原生 Office Open XML (.docx) 单文件生成器与 Markdown 打包器。
- `ParagraphReconstructor`：启发式离线段落重构引擎，负责断句合并与排版结构保护。
- `PageRangeParser`、`PDFProcessingConfiguration`：可独立测试的纯逻辑参数解析模块。
- `SidebarThumbnailView`、`PDFCanvasView`、`ResultInspectorView`、`SettingsView`、`WelcomeView`、`LaunchView`：原生用户界面组件。
