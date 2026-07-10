#!/bin/bash

# 核心逻辑测试不依赖完整 Xcode、XCTest 或第三方网络包。
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "${ROOT_DIR}"

SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)
ARCHITECTURE=$(uname -m)
DEPLOYMENT_TARGET="14.0"
BUILD_DIR=".build/core-tests"
MODULE_CACHE_DIR=".build/module-cache"
TEST_EXECUTABLE="${BUILD_DIR}/PDFExtractorCoreTests"

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

swiftc \
    -parse-as-library \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warn-concurrency \
    -warnings-as-errors \
    -sdk "${SDK_PATH}" \
    -target "${ARCHITECTURE}-apple-macosx${DEPLOYMENT_TARGET}" \
    -module-cache-path "${MODULE_CACHE_DIR}" \
    Sources/AIEndpoint.swift \
    Sources/OpenAIStreamParser.swift \
    Sources/PageRangeParser.swift \
    Sources/PDFProcessingConfiguration.swift \
    Tests/PDFExtractorCoreTests.swift \
    -o "${TEST_EXECUTABLE}"

"${TEST_EXECUTABLE}"
