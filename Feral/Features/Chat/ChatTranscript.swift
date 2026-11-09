import SwiftData
import SwiftUI

/// 对话流：当前会话的消息 + 正在流式说的那句 + 思考中提示。
///
/// 只画当前这一段——要翻别的会话走历史列表，不在同一屏上叠着显示。
struct ChatTranscript: View {
    let messages: [KimiChatMessage]
    let streamingText: String
    let streamingReasoning: String
    let isSending: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty && !isSending {
                        emptyHint
                    }
                    ForEach(messages) { message in
                        Bubble(message: message)
                    }
                    if isSending {
                        streamingBubble
                    }
                    // 滚动锚点：流式追加时把它滚进视野。
                    Color.clear.frame(height: 1).id(anchor)
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: streamingText) { _, _ in scrollToEnd(proxy) }
            .onChange(of: isSending) { _, _ in scrollToEnd(proxy) }
        }
    }

    private var anchor: String { "chat-bottom" }

    private var emptyHint: some View {
        Text("问点什么吧，比如「帮我写一段周报开头」。")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if streamingText.isEmpty {
                TypingIndicator(reasoning: streamingReasoning)
            } else {
                MarkdownText(text: streamingText)
                    .padding(10)
                    .background(bubbleBackground(for: .assistant), in: .rect(cornerRadius: 12))
                TypingIndicator(reasoning: "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(anchor, anchor: .bottom)
        }
    }
}

/// 一个气泡。助手消息走 markdown，用户消息是纯文本；附件显示在气泡上方。
struct Bubble: View {
    let message: KimiChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if !message.attachments.isEmpty {
                    attachmentsView
                }
                content
            }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !message.content.isEmpty {
            if message.role == .assistant {
                MarkdownText(text: message.content)
                    .padding(10)
                    .background(bubbleBackground(for: .assistant), in: .rect(cornerRadius: 12))
            } else {
                Text(message.content)
                    .padding(10)
                    .background(bubbleBackground(for: .user), in: .rect(cornerRadius: 12))
            }
        }
    }

    private var attachmentsView: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            ForEach(message.attachments.sorted { $0.createdAt < $1.createdAt }, id: \.id) { attachment in
                if attachment.kind == .image, let image = attachment.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 180, maxHeight: 180)
                        .clipShape(.rect(cornerRadius: 12))
                } else {
                    Label(attachment.fileName, systemImage: "doc.text")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.secondary.opacity(0.1), in: .capsule)
                }
            }
        }
    }
}

/// 气泡底色。用户淡强调色，助手淡灰。
func bubbleBackground(for role: ChatRole) -> Color {
    role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12)
}

/// 「思考中」提示。K3 会先想再答，思考增量有内容时就把最后一行露出来。
private struct TypingIndicator: View {
    let reasoning: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var label: String {
        let last = reasoning
            .components(separatedBy: .newlines)
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let last else { return "思考中…" }
        return String(last.prefix(40))
    }
}
