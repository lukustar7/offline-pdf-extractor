// swift-tools-version: 6.0

import PackageDescription

// Swift Package 清单用于统一最低系统版本、Swift 语言模式和自动测试入口。
let package = Package(
    name: "PDFTextExtractor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PDFExtractor", targets: ["PDFExtractor"])
    ],
    targets: [
        .executableTarget(
            name: "PDFExtractor",
            path: "Sources",
            swiftSettings: [
                .unsafeFlags([
                    "-strict-concurrency=complete",
                    "-warn-concurrency",
                    "-warnings-as-errors"
                ])
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
