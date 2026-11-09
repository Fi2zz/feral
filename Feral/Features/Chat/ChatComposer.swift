import SwiftUI

/// 输入条：圆角矩形，底部一行放「深度思考 / 智能搜索」与「＋ / 语音 / 发送」。
struct ChatComposer: View {
    @Binding var text: String
    let isSending: Bool
    let isSearching: Bool
    let attachments: [PendingAttachment]
    let imagesAllowed: Bool
    @Binding var deepThinking: Bool
    let deepThinkingAvailable: Bool
    @Binding var smartSearch: Bool
    let onRemoveAttachment: (UUID) -> Void
    let onPickPhotos: () -> Void
    let onPickFiles: () -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    private static let controlSize: CGFloat = 38
    private static let cornerRadius: CGFloat = 26

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !attachments.isEmpty {
                attachmentStrip
            }
            textField
            bottomRow
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .animation(.snappy(duration: 0.18), value: canSend)
        .animation(.snappy(duration: 0.18), value: attachments.count)
    }

    // MARK: - 文本

    private var textField: some View {
        TextField("发消息或按住说话", text: $text, axis: .vertical)
            .font(.body)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .focused($focused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - 底部一行

    private var bottomRow: some View {
        HStack(spacing: 8) {
            chip(
                title: "深度思考",
                icon: "brain.head.profile",
                active: deepThinking,
                enabled: deepThinkingAvailable,
                action: { deepThinking.toggle() }
            )
            chip(
                title: "智能搜索",
                icon: "globe",
                active: smartSearch,
                enabled: true,
                action: { smartSearch.toggle() }
            )
            Spacer(minLength: 4)
            plusButton
            trailingControl
        }
    }

    private func chip(
        title: String,
        icon: String,
        active: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .background(
                    active ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: - ＋

    private var plusButton: some View {
        Menu {
            Button {
                onPickPhotos()
            } label: {
                Label(imagesAllowed ? "照片" : "照片（当前模型不支持）", systemImage: "photo")
            }
            .disabled(!imagesAllowed)

            Button {
                onPickFiles()
            } label: {
                Label("文件", systemImage: "doc.text")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: Self.controlSize, height: Self.controlSize)
                .overlay {
                    Circle().strokeBorder(.primary.opacity(0.75), lineWidth: 1.5)
                }
        }
        .accessibilityLabel("添加附件")
    }

    // MARK: - 发送 / 停止 / 语音

    @ViewBuilder
    private var trailingControl: some View {
        if isSearching {
            ProgressView()
                .controlSize(.small)
                .frame(width: Self.controlSize, height: Self.controlSize)
                .accessibilityLabel("正在联网搜索")
        } else if isSending {
            circle(fill: .secondary.opacity(0.16), icon: "stop.fill", iconColor: .secondary, action: onStop)
        } else if canSend {
            circle(fill: .accentColor, icon: "arrow.up", iconColor: .white, action: send)
                .transition(.scale.combined(with: .opacity))
        } else {
            Image(systemName: "mic")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: Self.controlSize, height: Self.controlSize)
                .overlay {
                    Circle().strokeBorder(.secondary.opacity(0.35), lineWidth: 1.5)
                }
                .accessibilityLabel("语音输入（即将支持）")
        }
    }

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
    }

    // MARK: - 附件

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { item in
                    attachmentChip(item)
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentChip(_ item: PendingAttachment) -> some View {
        if let image = item.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topTrailing) { removeBadge(item.id) }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(item.fileName)
                    .font(.caption)
                    .lineLimit(1)
                removeBadge(item.id)
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 7)
            .background(.secondary.opacity(0.1), in: .capsule)
        }
    }

    private func removeBadge(_ id: UUID) -> some View {
        Button {
            onRemoveAttachment(id)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white, .black.opacity(0.5))
        }
        .buttonStyle(.plain)
        .padding(3)
        .accessibilityLabel("移除附件")
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private func send() {
        onSend()
        focused = true
    }
}
