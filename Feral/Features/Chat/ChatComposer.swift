import SwiftUI

/// 输入条：一颗高胶囊，尺寸对齐参考图（约 56pt 高，内嵌圆形按钮）。
///
/// 空的时候两侧干净（不挂附件、不挂语音），一旦有内容右侧才浮出发送键——
/// 这是图上那套的常见行为，也免得空状态堆一排用不上的按钮。
struct ChatComposer: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    /// 单行时的文字区高度。加上下面的垂直内边距就是胶囊总高。
    private static let textMinHeight: CGFloat = 24
    private static let textPadding: CGFloat = 15
    private static let controlSize: CGFloat = 34
    private static let controlInset: CGFloat = 11

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            field
            trailingControl
        }
        .background(.background, in: .capsule)
        .overlay {
            Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .animation(.snappy(duration: 0.18), value: canSend)
    }

    private var field: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.body)
            .lineLimit(1...5)
            .textFieldStyle(.plain)
            .focused($focused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Self.textMinHeight)
            .padding(.vertical, Self.textPadding)
            .padding(.leading, 20)
            .padding(.trailing, trailingInset)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isSending {
            circle(fill: .secondary.opacity(0.18), icon: "stop.fill", iconColor: .secondary, action: onStop)
        } else if canSend {
            circle(fill: .accentColor, icon: "arrow.up", iconColor: .white, action: send)
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// 圆形按钮：尺寸与右侧留白都跟文字区对齐，单行时看着在垂直居中。
    private func circle(
        fill: Color,
        icon: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: Self.controlSize, height: Self.controlSize)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
        }
        .buttonStyle(.plain)
        .padding(.trailing, Self.controlInset)
        .padding(.bottom, Self.controlInset)
    }

    /// 有按钮时文字区右边留窄一点，让按钮落进胶囊的圆角里。
    private var trailingInset: CGFloat {
        isSending || canSend ? 4 : 20
    }

    private var placeholder: String { "有问题尽管问，比如「帮我理一下今天的安排」" }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        onSend()
        focused = true
    }
}
