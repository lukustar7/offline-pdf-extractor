# PDF 本地文字提取工具

macOS 原生 PDF 图文提取与去水印工具。PDF 解析、Core Image 图像预处理、Vision OCR、插图定位截取与 Word (.docx) 导出均在本机纯离线完成。

## 功能

- 智能通道探测：导入时自动抽样探测矢量文本层，自动匹配极速文本层提取或 Vision OCR 通道。
- 图文与插图完整留存：自动定位并截取 PDF 电子版及扫描件中的图表与插图，按阅读顺序自然插入段落之间。
- 统一 Word (.docx) 导出：基于 Office Open XML 规范在本地生成包含段落排版与提取插图的文档文件；同时支持 Markdown 压缩包导出。
- 智能换行与段落重组：基于中西文标点终结符、英文连字符拼合（De-hyphenation）、缩写词白名单与段首缩进判定，自动合并异常断行，输出规整段落。
- 图像去水印与印章处理：通过色彩通道分离降低彩色印章干扰，结合色阶调整淡化浅灰背景水印；支持高频文本水印词检测与自定义词库过滤。
- 界面交互规范：遵循 macOS 人机交互指南 (HIG)，采用三栏布局与标准尺寸控件（36px/38px），支持连续纵向浏览、页面缩略图导航与独立偏好设置窗口 (⌘,)。

## PDF 场景

1. 可选文字 + 文字水印：适用于可选中复制文字的电子文档，直接提取矢量文本层与内嵌图像并保留排版结构。
2. 扫描正文 + 文字水印：适合正文为不可选图像但水印为后加文字的扫描件，自动滤除文字水印后通过 Vision OCR 识别文字并截取插图。
3. 扫描正文 + 纸印水印：适合正文与水印印章均打印在纸上的一体化扫描件，自动执行背景与印章净化预处理后再识别。

## 安全边界

- 100% 纯本地离线运行，应用未声明任何网络连接权限，不请求任何外部服务。
- 所有文本识别、图像分析与 Word 文档构建均在本地处理器完成，数据永不出设备。

## 环境

- macOS 14.0 或更高版本
- Apple Silicon (ARM64 架构，不支持 x86_64)
- Swift 6 Command Line Tools 或完整 Xcode（仅源码构建需要）

## 运行

直接打开项目根目录的 `PDF文字提取.app`。

## 验证与构建

```bash
./test.sh
./build.sh
./clean.sh
```

`test.sh` 执行 23 项零依赖核心逻辑与大文件压力测试。`build.sh` 会再次运行测试，随后针对 Apple Silicon (ARM64) 编译生成 Release App，执行本地签名并校验最低系统版本。`clean.sh` 可用于清理本地构建缓存。

## 结构

- `PDFExtractorEngine`：文件生命周期、任务控制、页面导航、缩略图状态与 Word/Markdown 导出调度。
- `PDFExtractionWorker`：后台 PDFKit 渲染、Core Image 通道去印与去水印滤镜、缩略图生成与 Vision OCR。
- `DocumentLayoutAnalyzer`：版面自适应插图外接矩形探测、文字网格遮蔽与纵向图文混排算法。
- `DocxDocumentBuilder`：macOS 原生 Office Open XML (.docx) 单文件生成器与 Markdown 打包器。
- `ParagraphReconstructor`：启发式离线段落重构引擎，负责断句合并与排版结构保护。
- `PageRangeParser`、`PDFProcessingConfiguration`：可独立测试的纯逻辑参数解析模块。
- `SidebarThumbnailView`、`PDFCanvasView`、`ResultInspectorView`、`SettingsView`、`WelcomeView`、`LaunchView`：原生用户界面组件。
