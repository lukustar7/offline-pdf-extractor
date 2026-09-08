---
name: "PDF Text & Watermark Extractor (PDF 文字提取与去水印)"
version: "1.3.0"
description: "Apple HIG compliant macOS native document productivity app design system. Features crystal-clear translucent vibrancy, physical paper elevation, zero-scroll inspector, and synchronized OCR workflow."
author: "Google Antigravity & Design Team"
specification: "Google Stitch Design MD v1.0 / W3C DTCG Aligned"

# ----------------------------------------------------------------------
# 1. MACHINE-READABLE DESIGN TOKENS
# ----------------------------------------------------------------------
colors:
  # Base Backgrounds & Surfaces (Native macOS Vibrant Semantics)
  window-background:
    light: "#F5F5F7"
    dark: "#1E1E1E"
    alpha-overlay: "rgba(255, 255, 255, 0.72)"
  canvas-background:
    light: "#ECECF0"
    dark: "#141416"
  sidebar-background:
    light: "rgba(246, 246, 248, 0.85)"
    dark: "rgba(36, 36, 38, 0.85)"
  card-background:
    light: "rgba(255, 255, 255, 0.82)"
    dark: "rgba(45, 45, 48, 0.82)"
  paper-surface:
    light: "#FFFFFF"
    dark: "#FFFFFF" # Physical paper always preserves true contrast
  
  # Text & Content Vibrancy (WCAG AA Compliant)
  text-primary:
    light: "#1D1D1F"
    dark: "#F5F5F7"
  text-secondary:
    light: "#86868B"
    dark: "#A1A1A6"
  text-tertiary:
    light: "#AEAEB2"
    dark: "#636366"
  
  # System Accents & Functional Indicators
  accent-primary:
    light: "#0071E3" # Apple Standard Blue
    dark: "#0A84FF"
  accent-secondary:
    light: "#5856D6" # Purple / AI Accent
    dark: "#5E5CE6"
  accent-success:
    light: "#34C759"
    dark: "#30D158"
  accent-warning:
    light: "#FF9500"
    dark: "#FF9F0A"
  accent-danger:
    light: "#FF3B30"
    dark: "#FF453A"

  # Borders & Separators
  border-subtle:
    light: "rgba(0, 0, 0, 0.08)"
    dark: "rgba(255, 255, 255, 0.12)"
  separator:
    light: "rgba(60, 60, 67, 0.18)"
    dark: "rgba(84, 84, 88, 0.35)"

typography:
  font-family-sans: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'SF Pro Display', 'Helvetica Neue', sans-serif"
  font-family-mono: "'SF Mono', Menlo, Monaco, Consolas, monospace"
  
  # Scale Hierarchy (Size / LineHeight / Weight)
  large-title:
    fontSize: "26px"
    lineHeight: "32px"
    fontWeight: "700"
    letterSpacing: "-0.4px"
  title:
    fontSize: "18px"
    lineHeight: "24px"
    fontWeight: "600"
    letterSpacing: "-0.2px"
  headline:
    fontSize: "14px"
    lineHeight: "20px"
    fontWeight: "600"
    letterSpacing: "-0.1px"
  body:
    fontSize: "13px"
    lineHeight: "18px"
    fontWeight: "400"
    letterSpacing: "0px"
  body-mono:
    fontFamily: "{typography.font-family-mono}"
    fontSize: "12px"
    lineHeight: "18px"
    fontWeight: "400"
  caption:
    fontSize: "11px"
    lineHeight: "14px"
    fontWeight: "400"
    letterSpacing: "0.1px"
  caption-bold:
    fontSize: "11px"
    lineHeight: "14px"
    fontWeight: "600"
  micro:
    fontSize: "9px"
    lineHeight: "12px"
    fontWeight: "500"

spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "40px"
  xxxl: "60px"

radius:
  sm: "4px"
  md: "8px"
  lg: "12px"
  xl: "16px"
  pill: "9999px"

elevation:
  paper-shadow:
    ambient: "0 1px 3px rgba(0, 0, 0, 0.06)"
    key: "0 12px 28px rgba(0, 0, 0, 0.12)"
  floating-hud:
    ambient: "0 4px 12px rgba(0, 0, 0, 0.14)"
    border: "0.5px solid {colors.border-subtle.light}"
  card-shadow:
    ambient: "0 2px 6px rgba(0, 0, 0, 0.04)"
  modal-sheet:
    ambient: "0 24px 48px rgba(0, 0, 0, 0.24)"

components:
  # Window Container
  app-window:
    minWidth: "1000px"
    minHeight: "700px"
    background: "{colors.window-background.light}"
    sidebarPlacement: "left"
    inspectorPlacement: "right"
  
  # Left Thumbnail Navigation Sidebar
  sidebar-thumbnail:
    width: "160px"
    minWidth: "130px"
    maxWidth: "220px"
    backgroundColor: "{colors.sidebar-background.light}"
    cardWidth: "120px"
    cardHeight: "160px"
    cardRadius: "{radius.sm}"
    activeBorderWidth: "2.5px"
    activeBorderColor: "{colors.accent-primary.light}"
  
  # Middle Canvas Area
  pdf-canvas:
    backgroundColor: "{colors.canvas-background.light}"
    paperRadius: "{radius.sm}"
    paperShadow: "{elevation.paper-shadow}"
    controlsCapsuleRadius: "{radius.pill}"
    controlsCapsuleBackground: "{elevation.floating-hud}"
  
  # Right Unified Result Inspector
  result-inspector:
    width: "320px"
    minWidth: "280px"
    maxWidth: "400px"
    backgroundColor: "{colors.sidebar-background.light}"
    configCardBackground: "{colors.card-background.light}"
    configCardRadius: "{radius.md}"
  
  # Primary & Action Buttons
  button-primary:
    backgroundColor: "{colors.accent-primary.light}"
    textColor: "#FFFFFF"
    height: "28px"
    radius: "{radius.md}"
    fontWeight: "600"
    fontSize: "{typography.body.fontSize}"
  
  button-bordered:
    backgroundColor: "transparent"
    border: "1px solid {colors.border-subtle.light}"
    textColor: "{colors.text-primary.light}"
    height: "24px"
    radius: "{radius.sm}"
    fontSize: "{typography.caption.fontSize}"
---

# PDF Text & Watermark Extractor — Design System Document (DESIGN.md)

This document is the authoritative design specification for **PDF Text & Watermark Extractor (macOS)**. It establishes the visual grammar, spatial layout rules, component tokens, micro-interactions, and accessibility constraints for human designers and AI design engines (e.g., Google Stitch, Figma AI, SwiftUI code generators).

---

## 1. Overview & Visual Identity

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 🌟 macOS Native Desktop Tri-Pane Workspace Architecture                         │
├───────────────────────┬─────────────────────────────────┬───────────────────────┤
│ Left: Page Thumbnails │ Center: Immersive Canvas        │ Right: Inspector      │
│ (130px - 220px)       │ (Adaptive Width >= 400px)       │ (280px - 400px)       │
│                       │                                 │                       │
│ • Aspect thumbnails   │ • Suspended 3D physical paper   │ • 0-Scroll config     │
│ • State badges        │ • Viewport floating capsule     │ • Mode segmentation   │
│ • Page jumping        │ • Scanning shimmer glow         │ • Markdown rich view  │
│ • Quick close file    │ • Before/After split comparison │ • Copy & Export       │
  ⚙️ Global App Settings (Word Export, Core Image Filters, Privacy) ➔ ⌘,
```

### 1.1 Design Philosophy: "Authentic Apple Craftsmanship"
- **Crystal-Clear Translucency (Vibrancy)**: Zero opaque murky gray layers (`.opacity(0.15)` sludge stacking is strictly prohibited). The window naturally breathes with the user's macOS desktop wallpaper using system `NSVisualEffectView` materials (`.sidebar`, `.underWindowBackground`, `.hudWindow`).
- **Physical Elevation & Paper Metaphor**: The PDF canvas simulates real paper floating above a frosted desk surface using dual-tier ambient and key shadows.
- **High Information Density with Zero Clutter**:
  - Global AI endpoints, API keys, and default system prompts are routed to the **macOS Settings Window (`⌘,`)**.
  - All redundant multi-line explanations are tucked into native **Tooltip Help Bubbles (`.help(...)`)**, keeping the inspector strictly **0-scroll (everything visible in 1 screen)**.

---

## 2. Colors & Material Hierarchy

### 2.1 Color Tokens Rationale
- **`window-background`**: Adapts dynamically between light (`#F5F5F7`) and dark (`#1E1E1E`). Blended behind the window to reveal wallpaper luminosity.
- **`accent-primary` (`#0071E3` / `#0A84FF`)**: Reserved exclusively for direct user confirmations, active tab pills, and the primary "Start Extraction (⌘R)" CTA.
- **`accent-secondary` (`#5856D6` / `#5E5CE6`)**: Dedicated to AI purification, LLM streaming indicators, and model status badges.
- **`paper-surface` (`#FFFFFF`)**: Always pure white regardless of dark mode, guaranteeing OCR text fidelity and scan accuracy.

### 2.2 Material Mapping Table
| UI Region | Material Type | Blending Mode | Visual Effect |
| :--- | :--- | :--- | :--- |
| **Window Frame** | `.windowBackground` | `behindWindow` | Wallpaper tint penetration |
| **Left Sidebar** | `.sidebar` | `behindWindow` | Subtle matte blur with separator |
| **Canvas Area** | `.underWindowBackground` | `behindWindow` | High contrast backdrop for paper |
| **Floating HUD Capsules** | `.hudWindow` | `withinWindow` | High-specular frosted glass with glow |
| **Modal Sheets** | `.popover` | `behindWindow` | Deep focused contrast |

---

## 3. Typography & Hierarchy

The interface strictly utilizes Apple's San Francisco system fonts (`SF Pro` and `SF Mono`).

```
Large Title  26pt / Bold       Onboarding headers, Welcome hero
Title        18pt / SemiBold   Document titles, Inspector tab headers
Headline     14pt / SemiBold   Section headers, Control group titles
Body         13pt / Regular    Labels, Form inputs, Button text
Body Mono    12pt / Regular    Extracted raw OCR text, Prompt editor
Caption      11pt / Regular    Secondary metadata, Page numbers, Tooltips
Micro         9pt / Medium     File size pills, status badges
```

- **Dynamic Contrast Rule**: Secondary labels (`#86868B`) must maintain a minimum contrast ratio of 4.5:1 against card backgrounds.
- **Monospace Alignment**: All raw extracted text and prompt editors use `SF Mono` with 1.4x line-height to prevent eye strain during proofreading.

---

## 4. Spacing, Layout & Spatial Grid

### 4.1 Spacing Scale
Based on the 4px / 8px incremental Apple HIG metric:
- **`xs` (4px)**: Gap between icon and text, micro-badge padding.
- **`sm` (8px)**: Distance between adjacent controls, horizontal padding in lists.
- **`md` (12px)**: Section spacing inside cards, standard container padding.
- **`lg` (16px)**: Window margin, main column padding.
- **`xl` (24px)**: Outer boundary margin on canvas.
- **`xxl` (40px)**: Hero empty state spacing.

### 4.2 Tri-Pane Proportions & Collapsibility
1. **Left Sidebar (Navigation)**:
   - Fixed width: `160px` (Resizable from `130px` to `220px`).
   - Collapsible via Toolbar leading button or `⌘⌥S`.
2. **Center Canvas (Immersive Preview)**:
   - Flexible width: Takes all remaining horizontal space (`>= 400px`).
   - Centers the PDF page with responsive auto-scaling.
3. **Right Inspector (Properties & Results)**:
   - Fixed width: `320px` (Resizable from `280px` to `400px`).
   - Collapsible via Toolbar trailing button or `⌘⌥I`.

---

## 5. Elevation, Depth & Motion

### 5.1 Physical Paper Elevation
The PDF page rendered in the central canvas adopts dual-layer composited shadows:
```css
/* Dual-layer Paper Shadow Specification */
box-shadow: 
  0 1px 3px rgba(0, 0, 0, 0.06),   /* Ambient occlusion at contact edge */
  0 12px 28px rgba(0, 0, 0, 0.12); /* Key directional light depth */
border: 0.5px solid rgba(0, 0, 0, 0.08);
border-radius: 4px;
```

### 5.2 Micro-Interactions & Animation Curves
- **Scanning Shimmer Glow (`scanningLightOverlay`)**:
  - Gradient: `LinearGradient(transparent, rgba(0,113,227,0.25), transparent)`
  - Duration: `1.6s` linear repeat-forever autoreverse during OCR and LLM streaming.
- **Sidebar & Inspector Toggle**:
  - Curve: `easeInOut(duration: 0.2s)` with simultaneous opacity fade.
- **Copy Feedback**:
  - Button state transitions to `[✓ 已复制]` in green for `1.5s`, then spring-transitions back.

---

## 6. Components Specification

### 6.1 Left Thumbnail Item (`ThumbnailRowItem`)
- **Dimensions**: Card `120px × 160px`, aspect-fit thumbnail rendering.
- **States**:
  - *Idle*: 0.5px subtle black border, standard shadow.
  - *Selected*: 2.5px solid `accent-primary` border, amplified 8px glow shadow, highlighted page pill.
  - *Status Badge (Top-Right)*:
    - `Processing`: Circular spinner scale 0.5.
    - `Extracted`: Solid green circle with white checkmark (`checkmark.circle.fill`).

### 6.2 Floating Viewport Capsule (`floatingViewportControls`)
- **Placement**: Top-right corner of the canvas, 16px inset.
- **Structure**: Rounded Capsule with `.hudWindow` material and 0.5px border.
- **Controls**: `[ + Zoom In ]` `[ - Zoom Out ]` `|` `[ Fit Window ]`.

### 6.3 0-Scroll Configuration Card (`inspectorConfigCard`)
- **Container**: `card-background` with `radius.md` and 0.5px separator.
- **Items**:
  1. *Scenario Picker*: 3-way Segmented Control (`电子文本` / `扫描正文` / `全扫描件`).
  2. *Watermark Toggles (Conditional)*: Checkbox with SF Symbol `questionmark.circle` (hover triggers detailed tooltip).
  3. *Page Range Menu*: Menu Picker (`全部页` / `当前页` / `指定范围`).

### 6.4 Document Studio Result Pane (`ResultInspectorView`)
- **Segmented Header**: Mini toggle between `[ 当前页对照 ]` (single page comparison) and `[ 全篇大纲 ]` (full document card stream).
- **Core Export**: Primary `[ 导出 Word (.docx) ]` single-file generation with lossless embedded images; secondary Menu for Markdown zip package and clipboard copy.
- **Illustration Cards**: Embedded figures cropped from scan/vector layers with right-click copy & save.

### 6.5 Settings Modal (`SettingsView` — `⌘,`)
- **Dimensions**: `520px × 380px` standard macOS preferences sheet.
- **Tabs**:
  1. `[ 导出与插图 ]`: Word (.docx) default settings, illustration extraction toggle, paragraph reconstruction.
  2. `[ 图像与去水印 ]`: Core Image level-stretch and red-channel filter toggles, case-sensitivity rules.
  3. `[ 隐私与关于 ]`: 100% offline security guarantee, version metadata.

---

## 7. Do’s and Don’ts (Design Constraints)

### ✅ DO
- **DO** maintain 100% offline visual privacy guarantees (green badges for local execution).
- **DO** use SF Symbols across all buttons and tabs with optical alignment.
- **DO** rely on standard macOS shortcuts (`⌘O` Open, `⌘R` Extract, `⌘,` Settings, `⌘⌥S` Toggle Left, `⌘⌥I` Toggle Right).
- **DO** keep controls spacious (36px/38px) and accessible.

### ❌ DON'T
- **DON'T** stack multiple semi-transparent gray backgrounds (`.background(Color.gray.opacity(0.15))` is forbidden).
- **DON'T** make network requests or declare network permissions.
- **DON'T** use custom non-native window titlebars or alien UI widgets.
- **DON'T** lock the UI thread during thumbnail generation or multi-page OCR.

---

## 8. Handover & Implementation Mapping

When generating frontend code from this specification, map tokens directly to the following codebase architecture:

```
Design Token Path                     SwiftUI / AppKit Target
─────────────────────────────────────────────────────────────────────────────
colors.window-background              VisualEffectView(material: .windowBackground)
colors.sidebar-background             VisualEffectView(material: .sidebar)
colors.canvas-background              VisualEffectView(material: .underWindowBackground)
elevation.paper-shadow                Theme.Shadow.paper(View) / .paperShadow()
elevation.floating-hud                Theme.Shadow.floating(View) / .floatingHUDShadow()
radius.md                             Theme.Radius.md (10pt)
components.sidebar-thumbnail          Sources/SidebarThumbnailView.swift
components.pdf-canvas                 Sources/PDFCanvasView.swift & PDFPreviewView.swift
components.result-inspector           Sources/ResultInspectorView.swift
components.settings-modal             Sources/SettingsView.swift
components.welcome-sheet              Sources/WelcomeView.swift
components.launch-dropzone            Sources/LaunchView.swift
```

---
*End of Design Specification. Generated in compliance with Google Stitch Design MD guidelines.*
