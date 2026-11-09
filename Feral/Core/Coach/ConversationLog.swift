import Foundation

/// 一次会话的摘要。列表里显示它就是这些，标题取第一条用户消息。
struct ConversationSummary: Identifiable, Equatable {
    var id: UUID
    var title: String
    var messageCount: Int
    var lastActiveAt: Date

    /// 列表里的时间：今天给时分，更早给月日。
    var timeText: String {
        Calendar.current.isDateInToday(lastActiveAt)
            ? Self.timeFormatter.string(from: lastActiveAt)
            : DateFormat.monthDayText(lastActiveAt)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// 会话从消息里推导，不另建一张表——省掉「会话表与消息不同步」这类问题。
///
/// 空会话（开了还没说话）不会出现在列表里：它没有消息，也就没什么可显示的。
/// 当前会话由 `KimiConversationStore` 记住，不靠列表推断。
enum ConversationLog {
    /// 按最近活动倒序。`limit` 防止列表无限长。
    static func summaries(from messages: [KimiChatMessage], limit: Int = 50) -> [ConversationSummary] {
        let grouped = Dictionary(grouping: messages, by: \.conversationID)
        let summaries = grouped.compactMap { id, items -> ConversationSummary? in
            guard let lastActiveAt = items.map(\.createdAt).max() else { return nil }
            return ConversationSummary(
                id: id,
                title: title(of: items),
                messageCount: items.count,
                lastActiveAt: lastActiveAt
            )
        }
        return Array(summaries.sorted { $0.lastActiveAt > $1.lastActiveAt }.prefix(limit))
    }

    static func messages(_ all: [KimiChatMessage], in conversationID: UUID) -> [KimiChatMessage] {
        all.filter { $0.conversationID == conversationID }
    }

    /// 第一条用户消息的第一行，截断到 24 个字。
    private static func title(of messages: [KimiChatMessage]) -> String {
        let first = messages
            .filter { $0.role == .user }
            .min { $0.createdAt < $1.createdAt }?
            .content
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first, !first.isEmpty else { return "（只有回答）" }
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= 24 ? trimmed : String(trimmed.prefix(24)) + "…"
    }
}
