import SwiftUI

// MARK: - 文件信息卡片视图
struct FileInfoView: View {
    let name: String
    let size: String
    let pages: Int
    var onClear: () -> Void
    
    // 弹窗二次确认状态，防止用户误触清空所有提取元数据 (P3-5 修复)
    @State private var showConfirm = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    
                    Text("\(size)  •  共 \(pages) 页")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    showConfirm = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                // 绑定无障碍描述
                .accessibilityLabel("关闭并卸载文件")
                .accessibilityHint("点击将彻底清除当前 PDF 加载状态及已提取文本")
                // 挂载误触确认弹窗 (P3-5 修复)
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
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
        // 卡片整体无障碍适配 (P3-7 修复)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("已加载的 PDF 文件：\(name)")
        .accessibilityValue("文件大小 \(size)，总计 \(pages) 页")
    }
}
