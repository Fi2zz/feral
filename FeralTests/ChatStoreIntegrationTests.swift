import Foundation
import Testing

@testable import Feral

/// ChatStore 层真打到假服务上的联调用例（落消息、流式草稿、会话历史）。
/// 运行时层的联调在 CoachIntegrationTests；假服务探针在 MockKimiServer.swift。
///
/// 只在假服务起着的时候跑（`make test-llm` 会先把它拉起来），平时 `make test`
/// 自动跳过，不因为「本机没起服务」而红。
@Suite("ChatStore 联调", .enabled(if: MockKimiServer.reachable), .serialized)
@MainActor
struct ChatStoreIntegrationTests {
    @Test("ChatStore 发一轮：落两条消息、不发失败")
    func chatStoreRoundTrip() async throws {
        setenv("KIMI_BASE_URL", MockKimiServer.baseUrl, 1)
        let restoreProvider = MockKimiServer.pinKimiProvider()
        defer { restoreProvider() }
        try CoachKeyStore.save("sk-mock", provider: .kimi)

        let runtimeStore = RuntimeStore()
        runtimeStore.start()
        defer { unsetenv("KIMI_BASE_URL") }
        let restoreKey = MockKimiServer.stashKey()
        defer { restoreKey() }
        try await waitUntilBooted(runtimeStore)

        let store = ChatStore(modelContext: TestStore.context, runtime: runtimeStore)
        await store.send("在吗")

        #expect(store.failure == nil)
        #expect(store.messages.count == 2)
        #expect(store.messages.first?.role == .user)
        #expect(store.messages.last?.role == .assistant)
        #expect(store.messages.last?.content.contains("（mock）收到了") == true)
    }

    @Test("ChatStore 流式：收完落一条助手消息，草稿清空")
    func chatStoreStreamsThenPersists() async throws {
        setenv("KIMI_BASE_URL", MockKimiServer.baseUrl, 1)
        defer { unsetenv("KIMI_BASE_URL") }
        let restoreProvider = MockKimiServer.pinKimiProvider()
        defer { restoreProvider() }
        let restoreKey = MockKimiServer.stashKey()
        defer { restoreKey() }
        try CoachKeyStore.save("sk-mock", provider: .kimi)

        let runtimeStore = RuntimeStore()
        runtimeStore.start()
        try await waitUntilBooted(runtimeStore)

        let store = try freshStore(runtimeStore: runtimeStore)
        await store.send("在吗")

        #expect(store.failure == nil)
        #expect(store.messages.count == 2)
        #expect(store.messages.last?.content.contains("（mock）收到了") == true)
        #expect(store.streamingText.isEmpty, "收完草稿要清掉，否则界面上会重影")
        #expect(store.isSending == false)
    }

    @Test("开新会话之后，下一次请求真的不带旧历史")
    func newConversationDropsHistory() async throws {
        setenv("KIMI_BASE_URL", MockKimiServer.baseUrl, 1)
        defer { unsetenv("KIMI_BASE_URL") }
        let restoreProvider = MockKimiServer.pinKimiProvider()
        defer { restoreProvider() }
        let restoreKey = MockKimiServer.stashKey()
        defer { restoreKey() }
        try CoachKeyStore.save("sk-mock", provider: .kimi)

        let runtimeStore = RuntimeStore()
        runtimeStore.start()
        try await waitUntilBooted(runtimeStore)
        let store = try freshStore(runtimeStore: runtimeStore)

        await store.send("第一句")
        let firstReply = try #require(store.messages.last?.content)
        await store.send("第二句")
        let secondReply = try #require(store.messages.last?.content)
        store.startNewConversation()
        await store.send("第三句")
        let thirdReply = try #require(store.messages.last?.content)

        // 假服务把收到几条历史回述出来，所以这三条断言的是「真发出去的东西」。
        #expect(firstReply.contains("历史消息 0 条"))
        #expect(secondReply.contains("历史消息 2 条"), "同一会话里第二轮带上一问一答")
        #expect(thirdReply.contains("历史消息 0 条"), "新会话不该带旧历史")
    }

    @Test("切回历史会话能接着聊：请求里带上那一段的历史")
    func resumingHistoryCarriesItsOwnHistory() async throws {
        setenv("KIMI_BASE_URL", MockKimiServer.baseUrl, 1)
        defer { unsetenv("KIMI_BASE_URL") }
        let restoreProvider = MockKimiServer.pinKimiProvider()
        defer { restoreProvider() }
        let restoreKey = MockKimiServer.stashKey()
        defer { restoreKey() }
        try CoachKeyStore.save("sk-mock", provider: .kimi)

        let runtimeStore = RuntimeStore()
        runtimeStore.start()
        try await waitUntilBooted(runtimeStore)
        let store = try freshStore(runtimeStore: runtimeStore)

        await store.send("第一句")
        let firstConversation = store.conversationID
        store.startNewConversation()
        await store.send("新会话第一句")

        // 回到第一段，接着问
        store.switchTo(firstConversation)
        #expect(store.messages.count == 2, "切回来看到的是那一段")
        await store.send("接着问")

        #expect(store.messages.count == 4, "第一段现在是一问一答再加一问一答")
        let reply = try #require(store.messages.last?.content)
        #expect(reply.contains("历史消息 2 条"), "接着聊要带上这段的一问一答，而不是新会话那两句")
    }

    @Test("OpenCode Go 请求带上当前会话的 x-opencode-session")
    func openCodeGoSessionHeader() async throws {
        setenv("OPENCODE_GO_BASE_URL", MockKimiServer.baseUrl, 1)
        defer { unsetenv("OPENCODE_GO_BASE_URL") }
        let restoreProvider = MockKimiServer.pinProvider(.openCodeGo)
        defer { restoreProvider() }
        let restoreKey = MockKimiServer.stashKey(provider: .openCodeGo)
        defer { restoreKey() }
        try CoachKeyStore.save("sk-mock", provider: .openCodeGo)

        let runtimeStore = RuntimeStore()
        runtimeStore.start()
        try await waitUntilBooted(runtimeStore)
        let store = try freshStore(runtimeStore: runtimeStore)

        await store.send("在吗")

        #expect(store.failure == nil)
        let reply = try #require(store.messages.last?.content)
        #expect(reply.contains("x-opencode-session：\(store.conversationID.uuidString)"))
    }

    /// 一条用例一段独立会话。测试共用 `TestStore.context` 这一个消息库，如果都用
    /// 默认的「遗留会话」id，别的用例的消息就会混进来（历史条数、消息条数全不准）。
    private func freshStore(runtimeStore: RuntimeStore) throws -> ChatStore {
        let defaults = try #require(UserDefaults(suiteName: "mock-chat-\(UUID().uuidString)"))
        KimiConversationStore.startNew(in: defaults)
        let store = ChatStore(
            modelContext: TestStore.context,
            runtime: runtimeStore,
            defaults: defaults
        )
        store.reload()
        return store
    }

    /// 装配是异步的，轮询到就绪为止；超时当失败，免得后面报出难懂的错。
    private func waitUntilBooted(_ store: RuntimeStore) async throws {
        for _ in 0..<40 {
            if case .ready = store.state { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(50))
        }
        Issue.record("运行时没在 2 秒内装好：\(store.state.label)")
    }
}
