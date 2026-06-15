#!/bin/bash

# 确保脚本发生任何错误时直接退出
set -e

echo "=== 开始编译并打包 macOS PDF去水印文字提取工具 (v1.7.1) ==="

# 1. 定义应用名称和目录结构
APP_NAME="PDF文字提取"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# 2. 清理历史构建产物
echo "清理历史构建..."
rm -rf "${APP_DIR}"
rm -f PDFExtractor
rm -rf AppIcon.iconset
rm -f AppIcon.icns

# 3. 创建 macOS App 包的目录结构
echo "创建 App 目录结构..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 4. 图标生成逻辑 (sips + iconutil)
if [ -f "app_icon.png" ]; then
    echo "检测到原始图标文件 app_icon.png，正在自动生成 macOS 官方图标包 AppIcon.icns..."
    
    ICONSET_DIR="AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"
    
    # 显式指定 -s format png，将输入的 JPEG 强制转码为合法的 PNG
    sips -s format png -z 16 16     app_icon.png --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null 2>&1
    sips -s format png -z 32 32     app_icon.png --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null 2>&1
    sips -s format png -z 32 32     app_icon.png --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null 2>&1
    sips -s format png -z 64 64     app_icon.png --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null 2>&1
    sips -s format png -z 128 128   app_icon.png --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null 2>&1
    sips -s format png -z 256 256   app_icon.png --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null 2>&1
    sips -s format png -z 256 256   app_icon.png --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null 2>&1
    sips -s format png -z 512 512   app_icon.png --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null 2>&1
    sips -s format png -z 512 512   app_icon.png --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null 2>&1
    sips -s format png -z 1024 1024 app_icon.png --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null 2>&1
    
    echo "正在转换成 icns..."
    iconutil -c icns "${ICONSET_DIR}" -o AppIcon.icns
    
    # 移动到 App 资源包下
    mv AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
    
    # 清理临时生成的 iconset 目录
    rm -rf "${ICONSET_DIR}"
    
    echo "AppIcon.icns 生成并打包成功！"
else
    echo "未检测到 app_icon.png，应用将使用 macOS 系统默认空白图标。"
fi

# 5. 编译 Swift 代码
echo "编译 Swift 源码 (main.swift) 中，请稍候..."
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)

swiftc -parse-as-library -O -sdk "${SDK_PATH}" Sources/*.swift -o PDFExtractor

echo "编译成功！生成可执行程序。"

# 6. 打包应用
echo "正在打包成 macOS App..."
mv PDFExtractor "${MACOS_DIR}/PDFExtractor"
cp Info.plist "${CONTENTS_DIR}/Info.plist"

# 7. 设置执行权限
chmod +x "${MACOS_DIR}/PDFExtractor"

echo "=== 构建成功！ ==="
echo "应用已打包在当前目录下：'${APP_DIR}'"
echo "您可以直接双击 '${APP_DIR}' 启动运行，或者在终端中运行 'open ${APP_DIR}'。"
