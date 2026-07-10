#!/bin/bash

# 构建脚本在替换现有 App 前完成测试、编译、打包和签名，任何一步失败都会保留旧产物。
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "${ROOT_DIR}"

APP_NAME="PDF文字提取"
EXECUTABLE_NAME="PDFExtractor"
APP_DIR="${APP_NAME}.app"
DEPLOYMENT_TARGET="14.0"

SCRATCH_DIR=".build/swiftpm"
CACHE_DIR=".build/swiftpm-cache"
CONFIG_DIR=".build/swiftpm-config"
SECURITY_DIR=".build/swiftpm-security"
STAGING_ROOT=".build/app-staging"
STAGING_APP="${STAGING_ROOT}/${APP_NAME}.app"
STAGING_CONTENTS="${STAGING_APP}/Contents"
STAGING_MACOS="${STAGING_CONTENTS}/MacOS"
STAGING_RESOURCES="${STAGING_CONTENTS}/Resources"
PREVIOUS_APP=".build/previous-${APP_NAME}.app"

echo "=== 构建 macOS PDF 文字提取工具 v0.3.0 ==="

echo "1/6 校验配置并运行核心测试..."
plutil -lint Info.plist >/dev/null
./test.sh

echo "2/6 使用 Swift 6 发布配置编译..."
mkdir -p "${CACHE_DIR}" "${CONFIG_DIR}" "${SECURITY_DIR}"
SWIFT_BUILD_OPTIONS=(
    --cache-path "${CACHE_DIR}"
    --config-path "${CONFIG_DIR}"
    --security-path "${SECURITY_DIR}"
    --scratch-path "${SCRATCH_DIR}"
    --configuration release
)

BIN_DIR=$(swift build "${SWIFT_BUILD_OPTIONS[@]}" --show-bin-path)
swift build "${SWIFT_BUILD_OPTIONS[@]}" --product "${EXECUTABLE_NAME}"

echo "3/6 创建临时 App 包..."
rm -rf "${STAGING_ROOT}"
mkdir -p "${STAGING_MACOS}" "${STAGING_RESOURCES}"
cp "${BIN_DIR}/${EXECUTABLE_NAME}" "${STAGING_MACOS}/${EXECUTABLE_NAME}"
cp Info.plist "${STAGING_CONTENTS}/Info.plist"
chmod +x "${STAGING_MACOS}/${EXECUTABLE_NAME}"

echo "4/6 准备应用图标..."
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${STAGING_RESOURCES}/AppIcon.icns"
else
    echo "错误：缺少 AppIcon.icns，无法完成应用打包。" >&2
    exit 1
fi

echo "5/6 执行本地签名与包完整性校验..."
codesign --force --deep --sign - "${STAGING_APP}"
codesign --verify --deep --strict "${STAGING_APP}"

ACTUAL_MINIMUM_OS=$(otool -l "${STAGING_MACOS}/${EXECUTABLE_NAME}" \
    | awk '/minos/{print $2; exit}')
if [ "${ACTUAL_MINIMUM_OS}" != "${DEPLOYMENT_TARGET}" ]; then
    echo "错误：二进制最低系统版本为 ${ACTUAL_MINIMUM_OS}，预期为 ${DEPLOYMENT_TARGET}。" >&2
    exit 1
fi

echo "6/6 原子替换本地 App..."
rm -rf "${PREVIOUS_APP}"
if [ -d "${APP_DIR}" ]; then
    mv "${APP_DIR}" "${PREVIOUS_APP}"
fi

if mv "${STAGING_APP}" "${APP_DIR}"; then
    rm -rf "${PREVIOUS_APP}" "${STAGING_ROOT}"
else
    if [ -d "${PREVIOUS_APP}" ]; then
        mv "${PREVIOUS_APP}" "${APP_DIR}"
    fi
    echo "错误：无法替换 App，已恢复旧产物。" >&2
    exit 1
fi

echo "=== 构建完成：${APP_DIR}（最低 macOS ${DEPLOYMENT_TARGET}） ==="
