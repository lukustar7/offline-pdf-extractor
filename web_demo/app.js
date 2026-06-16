/**
 * ==========================================================================
 * JavaScript 交互核心逻辑：驱动高拟真 SwiftUI 风格 Web Demo
 * ==========================================================================
 */

document.addEventListener("DOMContentLoaded", () => {
    // 1. 初始化 DOM 节点引用
    const btnImport = document.getElementById("btnImport");
    const btnClear = document.getElementById("btnClear");
    const btnExtract = document.getElementById("btnExtract");
    const btnAIPurify = document.getElementById("btnAIPurify");
    
    const segmentButtons = document.querySelectorAll(".segment-btn");
    const tabContents = document.querySelectorAll(".tab-content");
    
    const fileInput = document.getElementById("fileInput");
    const emptyState = document.getElementById("emptyState");
    const workspaceArea = document.getElementById("workspaceArea");
    const dropZone = document.getElementById("dropZone");
    const btnSelectFile = document.getElementById("btnSelectFile");
    const btnUseDemo = document.getElementById("btnUseDemo");
    
    const metaFileName = document.getElementById("metaFileName");
    const metaFileDetails = document.getElementById("metaFileDetails");
    const extractionProgressContainer = document.getElementById("extractionProgressContainer");
    const progressBarFill = document.getElementById("progressBarFill");
    const progressText = document.getElementById("progressText");
    
    const originalTextContainer = document.getElementById("originalTextContainer");
    const purifiedTextContainer = document.getElementById("purifiedTextContainer");
    const originalLines = document.getElementById("originalLines");
    const purifiedLines = document.getElementById("purifiedLines");
    
    const statChars = document.getElementById("statChars");
    const statTime = document.getElementById("statTime");
    const statAITime = document.getElementById("statAITime");
    
    const btnCopyOriginal = document.getElementById("btnCopyOriginal");
    const btnCopyPurified = document.getElementById("btnCopyPurified");
    const btnExportTxt = document.getElementById("btnExportTxt");
    const btnExportMd = document.getElementById("btnExportMd");
    
    // 新增：高亮/原生大括号视图切换控制器节点引用 (忠于原作设计)
    const viewToggleContainer = document.getElementById("viewToggleContainer");
    const btnViewHighlight = document.getElementById("btnViewHighlight");
    const btnViewRaw = document.getElementById("btnViewRaw");
    
    const customWatermarks = document.getElementById("customWatermarks");
    const recommendedTags = document.getElementById("recommendedTags");
    const analysisCard = document.getElementById("analysisCard");
    const enableWatermarkFilter = document.getElementById("enableWatermarkFilter");
    const watermarkSubOptions = document.getElementById("watermarkSubOptions");
    const systemPromptInput = document.getElementById("systemPrompt");
    const errorBanner = document.getElementById("errorBanner");
    const btnCloseAlert = document.getElementById("btnCloseAlert");
    
    // 2. 模拟运行状态变量
    let loadedFile = null;
    let isExtracted = false;
    let isAIPurified = false;
    let aiPurifiedRawText = ""; // 核心：专门保存 100% 原始含大括号的 AI 输出文本，以保证“复制与导出”完全忠于原作
    let aiAccumulatedRawText = ""; // 流式打字过程中已输出的原始大括号文本
    let currentViewMode = "highlight"; // 当前视图模式：'highlight' (气泡色卡高亮) 或 'raw' (大括号原文)
    
    // 默认的系统提示词，与 Swift 代码中 @AppStorage 保持一致
    const defaultSystemPrompt = `你是一个极为严谨的文本排版与错别字纠正助手。你将接收一段由 OCR 引擎从扫描件中识别出的原始文本。
请执行以下处理：
1. 保持原文的主体段落结构和逻辑含义完全不变，切勿重写、扩写或精简正文内容。
2. 修复文本中由于 OCR 识别误差导致的可能错字、别字（例如把“而且”识别为“面且”，把“我们”识别为“我门”）。
3. 智能修复不合理的强行换行：只智能合并由于 OCR 扫描在行尾造成的生硬硬断行（本应是一句话但断开了）。必须保留原文中所有的自然段落结构！
4. 每当你在字词、排版、硬换行上修改了任何内容，你必须在修改后的内容旁边，紧随其后附上大括号，格式为：“【识别是：[原始错误/硬换行]，修改为：[修改后/合并内容]】”。
5. 只输出处理纠正后的最终文本，严禁夹带任何多余的开场白、解释、Markdown 标记或总结语！`;

    systemPromptInput.value = defaultSystemPrompt;

    // 3. 侧边栏 Tab 分栏选择器切换
    segmentButtons.forEach(btn => {
        btn.addEventListener("click", () => {
            segmentButtons.forEach(b => b.classList.remove("active"));
            btn.classList.add("active");
            
            const targetTab = btn.getAttribute("data-tab");
            tabContents.forEach(tab => {
                tab.classList.remove("active");
                if (tab.id === targetTab) {
                    tab.classList.add("active");
                }
            });
        });
    });

    // 水印总开关联动控制
    enableWatermarkFilter.addEventListener("change", (e) => {
        if (e.target.checked) {
            watermarkSubOptions.style.opacity = "1";
            watermarkSubOptions.style.pointerEvents = "auto";
        } else {
            watermarkSubOptions.style.opacity = "0.4";
            watermarkSubOptions.style.pointerEvents = "none";
        }
    });

    // 4. 模拟 PDF 加载动作
    function loadFile(fileName, fileSize, pagesCount) {
        loadedFile = { name: fileName, size: fileSize, pages: pagesCount };
        
        // 界面状态流转：隐藏空状态，展现工作区
        emptyState.classList.add("hidden");
        workspaceArea.classList.remove("hidden");
        
        // 更新顶部文件名和基本元数据
        metaFileName.textContent = fileName;
        metaFileDetails.textContent = `准备就绪 • 共 ${pagesCount} 页 • ${fileSize}`;
        
        // 激活工具栏相关功能控制按钮
        btnClear.classList.remove("hidden");
        btnExtract.classList.remove("hidden");
        btnImport.classList.add("hidden");
        
        // 模拟分析 PDF 前几页的“高频推荐水印词”
        showRecommendedWatermarks();
        
        // 复位文本区和状态
        resetExtractionState();
    }

    // 重置提取状态，确保再次导入或设置变更时逻辑闭环
    function resetExtractionState() {
        isExtracted = false;
        isAIPurified = false;
        aiPurifiedRawText = "";
        aiAccumulatedRawText = "";
        viewToggleContainer.style.display = "none"; // 还原隐藏视图切换器
        btnAIPurify.classList.add("hidden");
        btnExtract.classList.remove("hidden");
        
        originalTextContainer.innerHTML = "";
        purifiedTextContainer.innerHTML = `<div class="ai-empty-prompt">
            <svg class="sparkle-icon" viewBox="0 0 24 24"><path d="M12 2L9 9 2 12l7 3 3 7 3-7 7-3-7-3z"/></svg>
            <p>点击上方工具栏的“AI 智能净化”按钮，一键发送给本地大模型，进行离线拼写纠错、合并硬断行与规范化重排。</p>
        </div>`;
        
        originalLines.innerHTML = "";
        purifiedLines.innerHTML = "";
        
        statChars.textContent = "字数: 0";
        statTime.textContent = "提取耗时: --";
        statAITime.textContent = "AI 纠错耗时: --";
        
        btnCopyOriginal.disabled = true;
        btnCopyPurified.disabled = true;
        btnExportTxt.disabled = true;
        btnExportMd.disabled = true;
    }

    // 模拟智能扫描推荐水印
    function showRecommendedWatermarks() {
        analysisCard.classList.remove("hidden");
        
        const recommendations = [
            { text: "学科网独家", count: 24 },
            { text: "禁止复制商用", count: 12 },
            { text: "微信扫码领资料", count: 8 }
        ];
        
        recommendedTags.innerHTML = "";
        recommendations.forEach(rec => {
            const tag = document.createElement("span");
            tag.className = "watermark-tag";
            tag.innerHTML = `<span>+ ${rec.text}</span> <small>(${rec.count}次)</small>`;
            tag.addEventListener("click", () => {
                // 点击推荐词，一键追加到自定义水印输入框
                let current = customWatermarks.value.trim();
                if (current) {
                    if (!current.includes(rec.text)) {
                        customWatermarks.value = current + ", " + rec.text;
                    }
                } else {
                    customWatermarks.value = rec.text;
                }
                // 点击后有微小的弹性动画反馈
                tag.style.transform = "scale(0.9)";
                setTimeout(() => { tag.style.transform = "scale(1)"; }, 150);
            });
            recommendedTags.appendChild(tag);
        });
    }

    // 5. 绑定各种文件导入交互事件
    btnSelectFile.addEventListener("click", () => fileInput.click());
    btnImport.addEventListener("click", () => fileInput.click());
    
    fileInput.addEventListener("change", (e) => {
        if (e.target.files.length > 0) {
            const file = e.target.files[0];
            const sizeStr = (file.size / (1024 * 1024)).toFixed(2) + " MB";
            loadFile(file.name, sizeStr, 6);
        }
    });

    // 拖拽文件区高亮响应 (Drag and Drop UI Interactions)
    dropZone.addEventListener("dragover", (e) => {
        e.preventDefault();
        dropZone.classList.add("dragover");
    });

    dropZone.addEventListener("dragleave", () => {
        dropZone.classList.remove("dragover");
    });

    dropZone.addEventListener("drop", (e) => {
        e.preventDefault();
        dropZone.classList.remove("dragover");
        if (e.dataTransfer.files.length > 0) {
            const file = e.dataTransfer.files[0];
            if (file.type === "application/pdf" || file.name.endsWith(".pdf")) {
                const sizeStr = (file.size / (1024 * 1024)).toFixed(2) + " MB";
                loadFile(file.name, sizeStr, 8);
            } else {
                showError("文件类型不支持", "目前仅支持导入本地 PDF 格式的文件进行文字提取。");
            }
        }
    });

    // 弹出错误通知卡片 (代替原生的 Alert)
    function showError(title, msg) {
        errorTitle.textContent = title;
        errorMessage.textContent = msg;
        errorBanner.classList.remove("hidden");
    }

    btnCloseAlert.addEventListener("click", () => {
        errorBanner.classList.add("hidden");
    });

    // 使用内置示例文件演示，降低测试门槛
    btnUseDemo.addEventListener("click", () => {
        loadFile("2026年普通高等学校招生全国统一考试语文(A卷).pdf", "1.45 MB", 4);
    });

    // 关闭文件清除状态
    btnClear.addEventListener("click", () => {
        loadedFile = null;
        emptyState.classList.remove("hidden");
        workspaceArea.classList.add("hidden");
        btnClear.classList.add("hidden");
        btnExtract.classList.add("hidden");
        btnAIPurify.classList.add("hidden");
        btnImport.classList.remove("hidden");
        analysisCard.classList.add("hidden");
        errorBanner.classList.add("hidden");
        fileInput.value = "";
    });

    // 6. 模拟文字提取逻辑 (跑马灯进度 + 双通道提取)
    btnExtract.addEventListener("click", () => {
        if (!loadedFile) return;
        
        btnExtract.disabled = true;
        extractionProgressContainer.classList.remove("hidden");
        progressBarFill.style.width = "0%";
        progressText.textContent = "正在进行本地多线程净化与文字识别...";
        
        let progress = 0;
        const interval = setInterval(() => {
            progress += 8;
            if (progress > 100) progress = 100;
            progressBarFill.style.width = `${progress}%`;
            
            if (progress < 40) {
                progressText.textContent = "正在扫描活字水印并物理擦除 (第 1/4 页)...";
            } else if (progress < 70) {
                progressText.textContent = "正在调起本地 Vision OCR 进行高精度识别 (第 2/4 页)...";
            } else if (progress < 95) {
                progressText.textContent = "正在汇总各页面文本并生成临时文件 (第 4/4 页)...";
            } else {
                progressText.textContent = "文字提取完成！";
            }

            if (progress >= 100) {
                clearInterval(interval);
                setTimeout(() => {
                    extractionProgressContainer.classList.add("hidden");
                    renderOriginalText();
                    btnExtract.disabled = false;
                }, 400);
            }
        }, 120);
    });

    // 渲染原始 OCR 文本（模拟提取结果，留有错别字和水印活字）
    function renderOriginalText() {
        const hasWatermark = enableWatermarkFilter.checked;
        const filterWords = customWatermarks.value;
        
        // 构造一份故意带有 OCR 别字、换行缺陷和可能带有水印的原始文本
        let rawContent = "";
        
        if (!hasWatermark || !filterWords.includes("学科网独家")) {
            rawContent += "学科网独家  学科网独家\n";
        }
        rawContent += `第一部分 现代文阅读 (共35分)
一、 现代文阅读 I (本题共 5小题，19分)
阅读下面的文字，完成1~5题。
  材料一：
  人类的智慧不仅体现在创造新知，更体现在对既有知识的整理与净化。面且我门需要明确的是，知识的传播需要通畅的通道。`;
        
        if (!hasWatermark || !filterWords.includes("学科网独家")) {
            rawContent += " 学科网独家\n";
        } else {
            rawContent += "\n";
        }

        rawContent += `  然而，在现代数字网络中，信息的生硬硬换行
常常阻碍了语义的连贯性。要
去阅读并理解这些文献，我们必须进行精细的处理。`;

        if (!hasWatermark || !filterWords.includes("禁止复制商用")) {
            rawContent += "\n禁止复制商用  禁止复制商用";
        }

        originalTextContainer.textContent = rawContent;
        
        // 生成左侧行号
        generateLineNumbers(rawContent, originalLines);
        
        // 更新字数和提取耗时
        statChars.textContent = `字数: ${rawContent.length}字`;
        statTime.textContent = "提取耗时: 1.25秒";
        
        // 状态流转
        isExtracted = true;
        btnExtract.classList.add("hidden");
        btnAIPurify.classList.remove("hidden");
        btnCopyOriginal.removeAttribute("disabled");
        btnExportTxt.removeAttribute("disabled");
        
        // 自动切到 AI 设置提示红点
        document.querySelector('.ai-status-dot').classList.add('pulsing');
    }

    // 动态生成行号工具函数
    function generateLineNumbers(text, container) {
        const lines = text.split("\n");
        container.innerHTML = "";
        for (let i = 1; i <= lines.length; i++) {
            const num = document.createElement("div");
            num.textContent = i;
            container.appendChild(num);
        }
    }

    // 7. 核心亮点：模拟 AI 纠错净化流式打字与词级高亮对比解析
    // 渲染 AI 净化面板内容的通用函数，根据 currentViewMode 自适应
    function renderPurifiedText(rawText) {
        if (currentViewMode === "highlight") {
            // 解析大括号为高亮 HTML 标签
            return parseDiffText(rawText);
        } else {
            // 直接以普通文本展示大括号 (忠于原作 100% 原始数据)
            return rawText
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;");
        }
    }

    btnAIPurify.addEventListener("click", () => {
        if (!isExtracted || isAIPurified) return;
        
        btnAIPurify.disabled = true;
        const aiSpinner = document.getElementById("aiSpinner");
        aiSpinner.classList.remove("hidden");
        
        purifiedTextContainer.innerHTML = "";
        purifiedLines.innerHTML = "";
        aiAccumulatedRawText = "";
        
        // 模拟流式打字的源文本（带大括号的 AI 纠正标记，忠于原作）
        const aiRawStreamText = `第一部分 现代文阅读 (共35分)
一、 现代文阅读 I (本题共 5小题，19分)
阅读下面的文字，完成 1~5 题。
  材料一：
  人类的智慧不仅体现在创造新知，更体现在对既有知识的整理与净化。而且【识别是：面且，修改为：而且】我们【识别是：我门，修改为：我们】需要明确的是，知识的传播需要通畅的通道。
  然而，在现代数字网络中，信息的生硬【识别是：生硬硬，修改为：生硬】换行常常阻碍了语义的连贯性。要去【识别是：要\\n去，修改为：要去】阅读并理解这些文献，我们必须进行精细的处理。`;

        // 我们将打字机动画分成小字块流式输出
        let currentIndex = 0;
        
        // 启动 AI 计时器
        let elapsed = 0;
        const timeInterval = setInterval(() => {
            elapsed += 0.1;
        }, 100);

        function typeNextChunk() {
            if (currentIndex < aiRawStreamText.length) {
                currentIndex += 3;
                aiAccumulatedRawText = aiRawStreamText.substring(0, currentIndex);
                
                // 根据当前的视图模式渲染文本
                purifiedTextContainer.innerHTML = renderPurifiedText(aiAccumulatedRawText);
                
                // 同步生成右侧行号
                const linesSrc = currentViewMode === "highlight" ? purifiedTextContainer.innerText : aiAccumulatedRawText;
                generateLineNumbers(linesSrc, purifiedLines);
                
                // 滚动到底部
                purifiedTextContainer.scrollTop = purifiedTextContainer.scrollHeight;
                
                // 继续下一次打字
                setTimeout(typeNextChunk, 25);
            } else {
                // 打字结束，完成处理
                clearInterval(timeInterval);
                aiSpinner.classList.add("hidden");
                btnAIPurify.disabled = false;
                btnAIPurify.classList.add("hidden"); // AI 净化完成
                isAIPurified = true;
                aiPurifiedRawText = aiRawStreamText; // 缓存完整原始文本 (忠于原作)
                
                // 激活高亮/原生切换控制器的显示 (macOS 原生分段控制器体验)
                viewToggleContainer.style.display = "inline-flex";
                
                statAITime.textContent = `AI 纠错耗时: ${elapsed.toFixed(1)}秒`;
                btnCopyPurified.removeAttribute("disabled");
                btnExportMd.removeAttribute("disabled");
                
                document.querySelector('.ai-status-dot').classList.remove('pulsing');
            }
        }
        
        // 延迟一秒模拟连接本地 API 大模型就绪时间
        setTimeout(typeNextChunk, 800);
    });

    /**
     * 核心高亮转换正则解析器：
     * 将 "而且【识别是：面且，修改为：而且】" 
     * 转换为精美的绿色修改标签与红色删除标记：
     * `<span class="diff-item diff-delete" data-reason="OCR识别错误"><s>面且</s></span>`
     * `<span class="diff-item diff-insert" data-reason="本地 AI 纠正纠错">而且</span>`
     */
    function parseDiffText(rawText) {
        // 利用正则表达式捕获： 纠正词【识别是：错字，修改为：正字】
        // 考虑到流式传输中括号可能不全，我们匹配完整的括号
        const regex = /([^\s【]*)【识别是：(.*?)[，,]\s*修改为：(.*?)】/g;
        
        let html = rawText;
        
        // 逃逸 HTML 特殊字符防止 XSS 攻击
        html = html
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
            
        // 替换大括号标记为精美的对比色卡 HTML
        html = html.replace(regex, (match, prefix, wrong, right) => {
            const cleanWrong = wrong.replace(/\\n/g, "\n"); // 还原换行符展示
            return `<span class="diff-item diff-delete" data-reason="OCR 原始错误: ${cleanWrong.replace(/\n/g, ' ↵ ')}"><s>${cleanWrong}</s></span>` + 
                   `<span class="diff-item diff-insert" data-reason="AI 智能纠偏排版: 修正为 ${right}">${right}</span>`;
        });
        
        return html;
    }

    // 8. 辅助交互：一键复制到剪贴板与浮动通知提示 (忠于原作：复制与导出 100% 原始大括号文本)
    function setupCopyToClipboard(btn, textGetter) {
        btn.addEventListener("click", () => {
            const text = textGetter();
            navigator.clipboard.writeText(text).then(() => {
                const originalText = btn.textContent;
                btn.textContent = "已复制 ✔";
                btn.style.color = "var(--accent-green)";
                
                // 1.5 秒后复位按钮状态
                setTimeout(() => {
                    btn.textContent = originalText;
                    btn.style.color = "";
                }, 1500);
            });
        });
    }

    // 原始文本直接复制容器内的 textContent
    setupCopyToClipboard(btnCopyOriginal, () => originalTextContainer.textContent);
    
    // AI 净化文本的核心修复：100% 复制带有大括号的 AI 原始排版纠错数据 (忠于原作逻辑)
    setupCopyToClipboard(btnCopyPurified, () => {
        return aiPurifiedRawText ? aiPurifiedRawText : purifiedTextContainer.innerText;
    });

    // 9. 视图切换控制器事件绑定
    btnViewHighlight.addEventListener("click", () => {
        if (!isAIPurified) return;
        currentViewMode = "highlight";
        btnViewHighlight.classList.add("active");
        btnViewRaw.classList.remove("active");
        purifiedTextContainer.innerHTML = renderPurifiedText(aiAccumulatedRawText);
        generateLineNumbers(purifiedTextContainer.innerText, purifiedLines);
    });

    btnViewRaw.addEventListener("click", () => {
        if (!isAIPurified) return;
        currentViewMode = "raw";
        btnViewRaw.classList.add("active");
        btnViewHighlight.classList.remove("active");
        purifiedTextContainer.innerHTML = renderPurifiedText(aiAccumulatedRawText);
        generateLineNumbers(aiAccumulatedRawText, purifiedLines);
    });

    // 10. 双栏内容同步滚动对齐逻辑 (Synchronized Scrolling)，提升左右对照阅读体验
    const wrapperOriginal = document.querySelector("#paneOriginal .pane-content-wrapper");
    const wrapperPurified = document.querySelector("#panePurified .pane-content-wrapper");
    
    let isSyncingOriginal = false;
    let isSyncingPurified = false;
    
    wrapperOriginal.addEventListener("scroll", () => {
        if (!isSyncingPurified) {
            isSyncingOriginal = true;
            // 计算当前滚动的百分比
            const maxScrollTop = wrapperOriginal.scrollHeight - wrapperOriginal.clientHeight;
            const percentage = maxScrollTop > 0 ? wrapperOriginal.scrollTop / maxScrollTop : 0;
            // 按同等比例滚动右侧
            const targetScrollTop = percentage * (wrapperPurified.scrollHeight - wrapperPurified.clientHeight);
            wrapperPurified.scrollTop = targetScrollTop;
            
            // 稍作延迟重置标志，防止循环触发 scroll 事件
            setTimeout(() => { isSyncingOriginal = false; }, 50);
        }
    });
    
    wrapperPurified.addEventListener("scroll", () => {
        if (!isSyncingOriginal) {
            isSyncingPurified = true;
            // 计算当前滚动的百分比
            const maxScrollTop = wrapperPurified.scrollHeight - wrapperPurified.clientHeight;
            const percentage = maxScrollTop > 0 ? wrapperPurified.scrollTop / maxScrollTop : 0;
            // 按同等比例滚动左侧
            const targetScrollTop = percentage * (wrapperOriginal.scrollHeight - wrapperOriginal.clientHeight);
            wrapperOriginal.scrollTop = targetScrollTop;
            
            // 稍作延迟重置标志，防止循环触发 scroll 事件
            setTimeout(() => { isSyncingPurified = false; }, 50);
        }
    });

    // 11. 模拟文件导出动作（同样导出大括号纯文本/Markdown 格式，忠于原作）
    function setupExportSimulate(btn, fileType) {
        btn.addEventListener("click", () => {
            btn.textContent = "正在保存...";
            setTimeout(() => {
                btn.textContent = `已导出 ${fileType}`;
                showError("导出文件成功", `已为您离线生成并保存物理文件。可在 Finder 中查看相关文档。`);
                setTimeout(() => {
                    btn.textContent = `导出 ${fileType}`;
                }, 2000);
            }, 1000);
        });
    }

    setupExportSimulate(btnExportTxt, "TXT");
    setupExportSimulate(btnExportMd, "Markdown");
});
