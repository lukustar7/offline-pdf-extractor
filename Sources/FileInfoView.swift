import SwiftUI

// MARK: - 文件信息卡片视图
struct FileInfoView: View {
    let name: String
    let size: String
    let pages: Int
    var onClear: () -> Void
    
    // 弹窗二次确认状态，防止用户误触清空已提取文本与 AI 结果。
    @State private var showConfirm = false
    
    var body: some View {
        GroupBox {
            HStack {
                Image(systemName: "doc.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    
                    Text("\(size)  •  共 \(pages) 页")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    showConfirm = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                // 绑定无障碍描述
                .accessibilityLabel("关闭并卸载文件")
                .accessibilityHint("点击将彻底清除当前 PDF 加载状态及已提取文本")
                // 挂载误触确认弹窗。
                .alert("关闭当前文件", isPresented: $showConfirm) {
                    Button("确定关闭", role: .destructive) {
                        onClear()
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("关闭当前文件将导致已提取出来的文本和 AI 净化成果被清除，且无法撤销。您确定要关闭吗？")
                }
            }
        }
        // 卡片整体无障碍适配。
        .accessibilityElement(children: .combine)
        .accessibilityLabel("已加载的 PDF 文件：\(name)")
        .accessibilityValue("文件大小 \(size)，总计 \(pages) 页")
    }
}

#if canImport(PreviewsMacros)
#Preview {
    FileInfoView(
        name: "研究报告.pdf",
        size: "3.2 MB",
        pages: 24,
        onClear: {}
    )
    .frame(width: 320)
    .padding()
}
#endif
