import SwiftUI

// MARK: - 毛玻璃效果视图 (macOS 原生毛玻璃窗口)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#if canImport(PreviewsMacros)
#Preview {
    VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
        .frame(width: 360, height: 240)
}
#endif
