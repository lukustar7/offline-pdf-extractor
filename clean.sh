#!/bin/bash

# 一键清理编译缓存，将项目从 2.0GB 瘦身回几兆字节
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "${ROOT_DIR}"

BEFORE_SIZE=$(du -sh . 2>/dev/null | awk '{print $1}')
echo "正在清理 Swift 编译器缓存 (.build)..."

rm -rf .build

AFTER_SIZE=$(du -sh . 2>/dev/null | awk '{print $1}')
echo "清理完成！"
echo "清理前体积: ${BEFORE_SIZE}"
echo "清理后体积: ${AFTER_SIZE}"
