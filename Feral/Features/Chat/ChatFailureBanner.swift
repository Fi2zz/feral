import SwiftUI

/// 发不出去时在输入条上方说清楚，不静默失败。点一下就关掉。
struct ChatFailureBanner: View {
    let failure: String?
    let onDismiss: () -> Void

    var body: some View {
        if let failure {
            Button(action: onDismiss) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
            .buttonStyle(.plain)
        }
    }
}
