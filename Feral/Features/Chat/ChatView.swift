import SwiftData
import SwiftUI

/// 对话页：先选提供商、填 API Key 与模型，再聊天。
struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RuntimeStore.self) private var runtime

    @State var store: ChatStore?
    @State private var draft = ""
    @State private var keyFailure: String?
    @State var isShowingSettings = false
    @State var isShowingHistory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChatTranscript(
                    messages: store?.messages ?? [],
                    streamingText: store?.streamingText ?? "",
                    streamingReasoning: store?.streamingReasoning ?? "",
                    isSending: store?.isSending ?? false
                )
                ChatFailureBanner(failure: store?.failure, onDismiss: { store?.dismissFailure() })
                ChatComposer(
                    text: $draft,
                    isSending: store?.isSending ?? false,
                    onSend: send,
                    onStop: { store?.stop() }
                )
            }
            .navigationTitle("对话")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { historyButton }
                ToolbarItem(placement: .topBarTrailing) { newConversationButton }
                ToolbarItem(placement: .topBarTrailing) { keyButton }
            }
            .task { prepare() }
            .alert("保存失败", isPresented: keyFailureBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(keyFailure ?? "")
            }
            .sheet(isPresented: $isShowingHistory) {
                ConversationListSheet(
                    conversations: store?.conversations ?? [],
                    currentID: store?.conversationID ?? UUID(),
                    onSelect: { store?.switchTo($0) },
                    onDelete: { store?.deleteConversation($0) },
                    onStartNew: { startNewConversation() }
                )
            }
            .sheet(isPresented: $isShowingSettings) {
                CoachSettingsSheet(
                    state: runtime.state.label,
                    onSave: { saveKey($0, provider: $1) },
                    onClear: { clearKey($0) },
                    onProviderChange: { pickProvider($0) },
                    onModelChange: { pick($0) },
                    onReboot: { runtime.restart() }
                )
            }
        }
    }

    // MARK: - 交互

    func startNewConversation() {
        store?.startNewConversation()
        draft = ""
    }

    private func send() {
        let text = draft
        draft = ""
        _Concurrency.Task { await store?.send(text) }
    }

    private func saveKey(_ value: String, provider: CoachProvider) {
        do {
            if !value.isEmpty { try CoachKeyStore.save(value, provider: provider) }
            runtime.restart()
        } catch {
            keyFailure = error.localizedDescription
        }
    }

    private func clearKey(_ provider: CoachProvider) {
        do {
            try CoachKeyStore.clear(provider: provider)
            runtime.restart()
        } catch {
            keyFailure = error.localizedDescription
        }
    }

    /// 换提供商：先记住再重装，端点与凭据是装配时定死的。不关面板，方便来回试。
    private func pickProvider(_ provider: CoachProvider) {
        CoachProviderStore.save(provider)
        runtime.restart()
    }

    /// 换模型：先记住再重装，provider 的模型是装配时定死的。不关面板，方便来回试。
    private func pick(_ model: CoachModel) {
        CoachModelStore.save(model, provider: CoachProviderStore.selected())
        runtime.restart()
    }

    // MARK: - 组装

    private func prepare() {
        runtime.start()
        if let store {
            store.reload()
            return
        }
        let created = ChatStore(modelContext: modelContext, runtime: runtime)
        created.reload()
        store = created
    }

    private var keyFailureBinding: Binding<Bool> {
        Binding(get: { keyFailure != nil }, set: { if !$0 { keyFailure = nil } })
    }
}
