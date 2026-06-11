#!/bin/bash

# 确保脚本发生任何错误时直接退出
set -e

echo "=== 开始编译并打包 macOS PDF去水印文字提取工具 ==="

# 1. 定义应用名称和目录结构
APP_NAME="PDF文字提取"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# 2. 清理旧的编译产物
echo "清理历史构建..."
rm -rf "${APP_DIR}"
rm -f PDFExtractor

# 3. 创建 macOS App 包的目录结构
echo "创建 App 目录结构..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 4. 编译 Swift 代码
# -parse-as-library 指定这是一个有 @main 入口的应用库
# -O 开启编译优化
# -sdk 指定 macOS SDK 路径
echo "编译 Swift 源码 (main.swift) 中，请稍候..."
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)

swiftc -parse-as-library -O -sdk "${SDK_PATH}" main.swift -o PDFExtractor

echo "编译成功！生成可执行程序。"

# 5. 打包应用
echo "正在打包成 macOS App..."
mv PDFExtractor "${MACOS_DIR}/PDFExtractor"
cp Info.plist "${CONTENTS_DIR}/Info.plist"

# 6. 设置执行权限
chmod +x "${MACOS_DIR}/PDFExtractor"

echo "=== 构建成功！ ==="
echo "应用已打包在当前目录下：'${APP_DIR}'"
echo "您可以直接双击 '${APP_DIR}' 启动运行，或者在终端中运行 'open ${APP_DIR}'。"
