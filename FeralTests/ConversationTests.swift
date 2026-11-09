import Foundation
import SwiftData
import Testing

@testable import Feral

@MainActor
@Suite("会话分组", .serialized)
struct ConversationTests {
    @Test("没记录时落在遗留会话上，升级前的消息不会各自成一段")
    func defaultsToLegacyConversation() throws {
        #expect(KimiConversationStore.current(in: try isolated()) == KimiChatMessage.legacyConversation)
    }

    @Test("开新会话换一个 id，而且记得住")
    func startNewPersists() throws {
        let defaults = try isolated()
        let first = KimiConversationStore.startNew(in: defaults)
        #expect(first != KimiChatMessage.legacyConversation)
        #expect(KimiConversationStore.current(in: defaults) == first)

        let second = KimiConversationStore.startNew(in: defaults)
        #expect(second != first)
        #expect(KimiConversationStore.current(in: defaults) == second)
    }

    @Test("切到历史会话要记住，下次启动还在这段")
    func selectPersists() throws {
        let defaults = try isolated()
        let target = UUID()
        KimiConversationStore.select(target, in: defaults)

        #expect(KimiConversationStore.current(in: defaults) == target)
    }

    @Test("存了个坏值就退回遗留会话，不崩")
    func corruptValueFallsBack() throws {
        let defaults = try isolated()
        defaults.set("not-a-uuid", forKey: KimiConversationStore.defaultsKey)

        #expect(KimiConversationStore.current(in: defaults) == KimiChatMessage.legacyConversation)
    }

    @Test("界面只显示当前会话，旧的不叠在同一屏上")
    func screenShowsCurrentConversationOnly() throws {
        let store = try makeStore()
        let old = try isolatedConversationID()
        try insert(role: .user, content: "上一段的问", conversation: old)
        try insert(role: .assistant, content: "上一段的答", conversation: old)
        try insert(role: .user, content: "这次的问", conversation: store.conversationID)
        store.reload()

        #expect(store.messages.map(\.content) == ["这次的问"])
        #expect(store.recentTurns().map(\.content) == ["这次的问"])
        #expect(store.conversations.count == 2, "两段都在历史列表里")
    }

    @Test("历史最多带最近 6 条")
    func historyIsCapped() throws {
        let store = try makeStore()
        for index in 1...8 {
            try insert(role: .user, content: "第 \(index) 句", conversation: store.conversationID)
        }
        store.reload()

        let history = store.recentTurns()
        #expect(history.count == 6)
        #expect(history.first?.content == "第 3 句")
        #expect(history.last?.content == "第 8 句")
    }

    @Test("开新会话：界面清空，旧会话进列表")
    func startNewClearsScreenButKeepsHistory() throws {
        let store = try makeStore()
        try insert(role: .user, content: "旧问题", conversation: store.conversationID)
        store.reload()
        let oldID = store.conversationID

        store.startNewConversation()

        #expect(store.messages.isEmpty, "新会话是干净的一屏")
        #expect(store.recentTurns().isEmpty)
        #expect(store.conversationIsEmpty)
        #expect(store.conversations.map(\.id) == [oldID], "旧的没丢，在历史列表里")
    }

    @Test("切回历史会话：消息回来，历史跟上，还能接着聊")
    func switchBackResumesConversation() throws {
        let store = try makeStore()
        let oldID = try isolatedConversationID()
        try insert(role: .user, content: "帮我想个标题", conversation: oldID)
        try insert(role: .assistant, content: "给你三个方向", conversation: oldID)
        store.reload()
        store.startNewConversation()
        #expect(store.messages.isEmpty)

        store.switchTo(oldID)

        #expect(store.conversationID == oldID)
        #expect(store.messages.map(\.content) == ["帮我想个标题", "给你三个方向"])
        #expect(store.recentTurns().count == 2, "接着聊要带上这段的历史")
    }

    @Test("切到同一段是空操作，不做多余的重载")
    func switchToSameIsNoop() throws {
        let store = try makeStore()
        try insert(role: .user, content: "问题", conversation: store.conversationID)
        store.reload()

        store.switchTo(store.conversationID)

        #expect(store.messages.count == 1)
    }

    @Test("删掉当前会话：消息清掉，并开一段新的")
    func deleteCurrentStartsFresh() throws {
        let store = try makeStore()
        try insert(role: .user, content: "要删的", conversation: store.conversationID)
        store.reload()
        let doomed = store.conversationID

        store.deleteConversation(doomed)

        #expect(store.conversationID != doomed)
        #expect(store.messages.isEmpty)
        #expect(store.conversations.isEmpty)
    }

    @Test("删掉非当前会话不影响当前这段")
    func deleteOtherKeepsCurrent() throws {
        let store = try makeStore()
        let other = try isolatedConversationID()
        try insert(role: .user, content: "别人的", conversation: other)
        try insert(role: .user, content: "我的", conversation: store.conversationID)
        store.reload()
        let mine = store.conversationID

        store.deleteConversation(other)

        #expect(store.conversationID == mine)
        #expect(store.messages.map(\.content) == ["我的"])
        #expect(store.conversations.map(\.id) == [mine])
    }

    // MARK: - 夹具

    @MainActor
    private func makeStore() throws -> ChatStore {
        ChatStore(
            modelContext: try TestStore.freshContext(),
            runtime: RuntimeStore(),
            defaults: try isolated()
        )
    }

    @MainActor
    private func insert(role: ChatRole, content: String, conversation: UUID) throws {
        TestStore.context.insert(
            KimiChatMessage(role: role, content: content, conversationID: conversation)
        )
        try TestStore.context.save()
    }

    /// 一个跟默认值不同的会话 id，并且把它记进当前值，方便断言。
    private func isolatedConversationID() throws -> UUID {
        KimiConversationStore.startNew(in: try isolated())
    }

    private func isolated() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "conversation-tests-\(UUID().uuidString)"))
    }
}

@Suite("历史会话列表")
struct ConversationLogTests {
    @Test("标题取第一条用户消息，截到 24 字")
    func titleFromFirstUserMessage() throws {
        let id = UUID()
        let messages = [
            message(.user, "帮我想个标题", id, at: 100),
            message(.assistant, "给你三个方向", id, at: 200),
        ]

        #expect(ConversationLog.summaries(from: messages).first?.title == "帮我想个标题")
    }

    @Test("标题过长要截断")
    func titleIsTruncated() throws {
        let long = String(repeating: "长", count: 40)
        let summaries = ConversationLog.summaries(from: [message(.user, long, UUID(), at: 100)])

        let title = try #require(summaries.first?.title)
        #expect(title.count == 25, "24 个字加一个省略号")
        #expect(title.hasSuffix("…"))
    }

    @Test("只有回答没有提问时不空白")
    func titleFallback() throws {
        let summaries = ConversationLog.summaries(from: [message(.assistant, "我先说的", UUID(), at: 100)])

        #expect(summaries.first?.title == "（只有回答）")
    }

    @Test("标题取第一行，不带换行")
    func titleUsesFirstLine() throws {
        let text = "第一行\n第二行"
        let summaries = ConversationLog.summaries(from: [message(.user, text, UUID(), at: 100)])

        #expect(summaries.first?.title == "第一行")
    }

    @Test("按最近活动倒序，条数对得上")
    func sortedByRecentActivity() throws {
        let old = UUID()
        let fresh = UUID()
        let messages = [
            message(.user, "旧的", old, at: 100),
            message(.user, "新的", fresh, at: 300),
            message(.assistant, "新的回答", fresh, at: 400),
        ]

        let summaries = ConversationLog.summaries(from: messages)

        #expect(summaries.map(\.id) == [fresh, old])
        #expect(summaries.first?.messageCount == 2)
        #expect(summaries.last?.messageCount == 1)
    }

    @Test("超过上限只留最近的")
    func respectsLimit() throws {
        let messages = (0..<5).map { index in
            message(.user, "第 \(index) 句", UUID(), at: TimeInterval(index))
        }

        #expect(ConversationLog.summaries(from: messages, limit: 3).count == 3)
    }

    @Test("空输入不出列表")
    func emptyInput() {
        #expect(ConversationLog.summaries(from: []).isEmpty)
    }

    private func message(
        _ role: ChatRole,
        _ content: String,
        _ conversation: UUID,
        at offset: TimeInterval
    ) -> KimiChatMessage {
        KimiChatMessage(
            role: role,
            content: content,
            createdAt: Date(timeIntervalSince1970: offset),
            conversationID: conversation
        )
    }
}
