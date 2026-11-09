import SwiftUI

/// 历史会话：按最近活动倒序，点一条接着聊。空会话（开了还没说话）不会出现在这里。
struct ConversationListSheet: View {
    let conversations: [ConversationSummary]
    let currentID: UUID
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onStartNew: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if conversations.isEmpty {
                    Text("还没有会话。问一句就有了。")
                        .foregroundStyle(.secondary)
                }
                ForEach(conversations) { conversation in
                    row(conversation)
                }
            }
            .navigationTitle("历史会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onStartNew()
                        dismiss()
                    } label: {
                        Label("新会话", systemImage: "square.and.pencil")
                    }
                }
            }
        }
    }

    private func row(_ conversation: ConversationSummary) -> some View {
        Button {
            onSelect(conversation.id)
            dismiss()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleColumn(conversation)
                Spacer(minLength: 8)
                trailingInfo(conversation)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("删除", role: .destructive) {
                onDelete(conversation.id)
            }
        }
    }

    private func titleColumn(_ conversation: ConversationSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(conversation.messageCount) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func trailingInfo(_ conversation: ConversationSummary) -> some View {
        HStack(spacing: 6) {
            Text(conversation.timeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if conversation.id == currentID {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}
