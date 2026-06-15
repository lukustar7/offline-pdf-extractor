# Apple Design Context

## Product
- **Name**: PDF 本地去水印文字提取工具
- **Description**: macOS 平台下 100% 离线运行的 PDF 文字提取与去水印效率工具
- **Category**: Productivity / Utility
- **Stage**: Redesign (macOS Native HIG Alignment)

## Platforms
| Platform | Supported | Min OS | Notes |
|----------|-----------|--------|-------|
| iOS      | No        |        |       |
| iPadOS   | No        |        |       |
| macOS    | Yes       | 11.0   | macOS desktop application |
| tvOS     | No        |        |       |
| watchOS  | No        |        |       |
| visionOS | No        |        |       |

## Technology
- **UI Framework**: SwiftUI
- **Architecture**: Single-window (WindowGroup)
- **Apple Technologies**: PDFKit, Vision (OCR), SecKey (Keychain)

## Design System
- **Base**: Apple Human Interface Guidelines (macOS System Defaults)
- **Brand Colors**: System Accent Color (Purple/Blue gradients restricted to primary actions, elsewhere utilizing standard system materials)
- **Typography**: System Fonts (SF Pro / SF Mono for logs)
- **Dark Mode**: Supported (Adaptive System Light/Dark Theme)
- **Dynamic Type**: Supported (System accessibility text scaling)

## Accessibility
- **Target Level**: Baseline
- **Key Considerations**: Keyboard navigation, screen reader accessibility for PDF viewer metadata, high-contrast text contrast.

## Users
- **Primary Persona**: Office workers, researchers, and legal professionals dealing with watermarked or scanned PDFs.
- **Key Use Cases**: Bulk text extraction from corporate watermarked PDFs, offline OCR for scanned documents.
- **Known Challenges**: The existing UI mimics iOS mobile design paradigms (colored cards, customized collapsible expanders, simulated non-native tabs) which feels out-of-place on macOS.
