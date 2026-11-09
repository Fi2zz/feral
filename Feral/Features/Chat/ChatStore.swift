import Foundation
import SwiftData
import SwiftusCredentials
import SwiftusLLM
import Observation

/// 对话状态：消息、流式草稿、发送中、错误。对话只读，模型不写任何数据。
@MainActor
@Observable
final class ChatStore {
    /// 当前会话的消息。界面只显示这一段的，开新会话就是干净的一屏。
    private(set) var messages: [KimiChatMessage] = []
    /// 历史会话列表（含当前这条），按最近活动倒序。
    private(set) var conversations: [ConversationSummary] = []
    private(set) var isSending = false
    /// 正在流式接收的正文，界面拿它当「正在说的那句」渲染。
    private(set) var streamingText = ""
    /// 正在流式接收的思考过程（K3 会先想再答）。
    private(set) var streamingReasoning = ""
    /// 最近一次发问失败的原因。不静默失败：发不出去就要在界面上说清楚。
    private(set) var failure: String?

    /// 当前会话 id。历史只在这一段里取。
    private(set) var conversationID: UUID
    /// 当前会话里还没说过话。
    var conversationIsEmpty: Bool { messages.isEmpty }

    private let modelContext: ModelContext
    private let runtime: RuntimeStore
    private let defaults: UserDefaults
    /// 全量消息。列表要跨会话，界面只要当前那段，所以两份都留着，
    /// 免得每来一条消息都要重新查一遍库。
    private var allMessages: [KimiChatMessage] = []
    private var inFlight: _Concurrency.Task<Void, Never>?
    private static let maxTurns = 6

    init(
        modelContext: ModelContext,
        runtime: RuntimeStore,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.runtime = runtime
        self.defaults = defaults
        self.conversationID = KimiConversationStore.current(in: defaults)
    }

    /// 每次回到页面重新拉一遍：消息落库了，聊天历史要能跨启动看得到。
    /// 拉全量再挑出当前会话——列表要的是全部，界面要的是当前那段。
    func reload() {
        let descriptor = FetchDescriptor<KimiChatMessage>(sortBy: [SortDescriptor(\.createdAt)])
        apply(all: (try? modelContext.fetch(descriptor)) ?? [])
    }

    /// 开新会话：干净的一屏，模型的上下文从零开始。旧会话进历史列表，一条不丢。
    func startNewConversation() {
        stop()
        conversationID = KimiConversationStore.startNew(in: defaults)
        reload()
    }

    /// 切到某个历史会话继续聊。
    func switchTo(_ id: UUID) {
        guard id != conversationID else { return }
        stop()
        conversationID = id
        KimiConversationStore.select(id, in: defaults)
        reload()
    }

    /// 删掉整段会话。删的是当前那段就顺手开一段新的，不留空白状态。
    func deleteConversation(_ id: UUID) {
        let doomed = allMessages.filter { $0.conversationID == id }
        guard !doomed.isEmpty else { return }
        if id == conversationID { stop() }
        for message in doomed {
            modelContext.delete(message)
        }
        try? modelContext.save()
        if id == conversationID {
            conversationID = KimiConversationStore.startNew(in: defaults)
        }
        reload()
    }

    private func apply(all: [KimiChatMessage]) {
        allMessages = all
        messages = ConversationLog.messages(all, in: conversationID)
        conversations = ConversationLog.summaries(from: all)
    }

    /// 失败提示看过就收起来。
    func dismissFailure() {
        failure = nil
    }

    /// 发一句。流式接收：先建一条空的助手消息占位，增量往里填，收完落库。
    func send(_ question: String) async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        // 先取历史再记录：这一句要拼进前缀，不能同时又当历史发一遍。
        let history = recentTurns()
        record(role: .user, content: text)
        isSending = true
        failure = nil
        streamingText = ""
        streamingReasoning = ""

        let task = _Concurrency.Task { await receive(history: history, question: text) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// 停止生成。已经收到的部分照实留下，标一下是被停的。
    func stop() {
        inFlight?.cancel()
    }

    /// 收流：正文增量拼成答案，思考增量单独走，收完写一条助手消息。
    private func receive(history: [LlmMessage], question: String) async {
        defer { clearStreamingState() }
        do {
            let stream = try await runtime.askStream(
                question: question,
                conversation: history
            )
            try await consume(stream)
            commitAnswer()
        } catch is CancellationError {
            finishPartial()
        } catch {
            failure = ErrorText.reason(error)
        }
    }

    /// 边收边填。被取消时抛出去，交给上面按「已停止」收尾。
    private func consume(_ stream: AsyncThrowingStream<LlmStreamEvent, Error>) async throws {
        for try await event in stream {
            if _Concurrency.Task.isCancelled { throw CancellationError() }
            ingest(event)
        }
    }

    private func ingest(_ event: LlmStreamEvent) {
        switch event {
        case .textDelta(let delta):
            streamingText += delta
        case .reasoningDelta(let delta):
            streamingReasoning += delta
        case .done:
            break
        }
    }

    private func clearStreamingState() {
        isSending = false
        streamingText = ""
        streamingReasoning = ""
    }

    /// 流正常收完：落一条助手消息。空回复也如实说，不留一条看不出所以然的气泡。
    private func commitAnswer() {
        let answer = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        record(role: .assistant, content: answer.isEmpty ? "（模型没返回内容）" : answer)
    }

    /// 被中止：收到多少留多少。
    private func finishPartial() {
        let partial = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return }
        record(role: .assistant, content: partial + "\n\n（已停止）")
    }

    /// 只把**当前会话**的最近几轮交给模型：避免越聊越贵，也避免上一段会话的
    /// 话题把新会话带偏。
    func recentTurns() -> [LlmMessage] {
        messages
            .filter { $0.conversationID == conversationID }
            .suffix(ChatStore.maxTurns)
            .map { LlmMessage($0.role == .user ? "user" : "assistant", $0.content) }
    }

    private func record(role: ChatRole, content: String) {
        let message = KimiChatMessage(role: role, content: content, conversationID: conversationID)
        modelContext.insert(message)
        try? modelContext.save()
        messages.append(message)
        allMessages.append(message)
        conversations = ConversationLog.summaries(from: allMessages)
    }
}
