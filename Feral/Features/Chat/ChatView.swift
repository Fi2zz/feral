import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 对话页：先选提供商、填 API Key 与模型，再聊天。
struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RuntimeStore.self) private var runtime

    @State var store: ChatStore?
    @State private var draft = ""
    @State private var keyFailure: String?
    @State private var attachmentError: String?
    @State private var attachments: [PendingAttachment] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isPickingPhotos = false
    @State private var isPickingFiles = false
    @State private var deepThinking = ReasoningEffortStore.selected() == .max
    @State private var smartSearch = SearchSettings.enabled()
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
                if store?.isSearching == true {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在联网搜索…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
                }
                ChatComposer(
                    text: $draft,
                    isSending: store?.isSending ?? false,
                    isSearching: store?.isSearching ?? false,
                    attachments: attachments,
                    imagesAllowed: imagesAllowed,
                    deepThinking: $deepThinking,
                    deepThinkingAvailable: deepThinkingAvailable,
                    smartSearch: $smartSearch,
                    onRemoveAttachment: { id in attachments.removeAll { $0.id == id } },
                    onPickPhotos: { isPickingPhotos = true },
                    onPickFiles: { isPickingFiles = true },
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
            .onChange(of: deepThinking) { _, on in
                ReasoningEffortStore.save(on ? .max : .high)
            }
            .onChange(of: smartSearch) { _, on in
                SearchSettings.save(enabled: on)
            }
            .onChange(of: isShowingSettings) { _, showing in
                if !showing {
                    deepThinking = ReasoningEffortStore.selected() == .max
                }
            }
            .onChange(of: photoSelection) { _, items in
                guard !items.isEmpty else { return }
                let remaining = max(0, ImageLoader.maxImages - imageCount)
                let picked = Array(items.prefix(remaining))
                photoSelection = []
                _Concurrency.Task { await addImages(picked) }
            }
            .photosPicker(
                isPresented: $isPickingPhotos,
                selection: $photoSelection,
                maxSelectionCount: ImageLoader.maxImages,
                matching: .images
            )
            .fileImporter(
                isPresented: $isPickingFiles,
                allowedContentTypes: TextFileLoader.allowedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): urls.forEach(addTextFile)
                case .failure(let error): attachmentError = error.localizedDescription
                }
            }
            .alert("保存失败", isPresented: keyFailureBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(keyFailure ?? "")
            }
            .alert("附件", isPresented: attachmentErrorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(attachmentError ?? "")
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

    // MARK: - 动作

    func startNewConversation() {
        store?.startNewConversation()
        draft = ""
        attachments = []
    }

    private func send() {
        let text = draft
        let pending = attachments
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty else { return }
        guard imagesAllowed || !pending.contains(where: \.isImage) else {
            attachmentError = "当前模型不支持图片，请切换到支持视觉的模型。"
            return
        }
        draft = ""
        attachments = []
        _Concurrency.Task {
            await store?.send(text, attachments: pending, searchEnabled: smartSearch)
        }
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

    // MARK: - 附件

    @MainActor
    private func addImages(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            do {
                attachments.append(try ImageLoader.load(data: data))
            } catch {
                attachmentError = error.localizedDescription
            }
        }
    }

    private func addTextFile(_ url: URL) {
        do {
            var attachment = try TextFileLoader.load(url: url)
            guard case .textFile(_, let name, let text) = attachment else { return }
            let remaining = max(0, TextFileLoader.maxTotalChars - textCharCount)
            guard remaining > 0 else {
                attachmentError = "文本附件总字数已达上限（\(TextFileLoader.maxTotalChars) 字）。"
                return
            }
            if text.count > remaining {
                attachment = .textFile(name: name, text: TextFileLoader.truncate(text, to: remaining))
            }
            attachments.append(attachment)
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private var imageCount: Int {
        attachments.filter(\.isImage).count
    }

    private var textCharCount: Int {
        attachments.compactMap(\.text).reduce(0) { $0 + $1.count }
    }

    // MARK: - 组装

    private func prepare() {
        runtime.start()
        deepThinking = ReasoningEffortStore.selected() == .max
        if let store {
            store.reload()
            return
        }
        let created = ChatStore(modelContext: modelContext, runtime: runtime)
        created.reload()
        store = created
    }

    private var deepThinkingAvailable: Bool {
        CoachLlmConfig.selectedModel.acceptsReasoningEffort
    }

    private var imagesAllowed: Bool {
        CoachLlmConfig.selectedModel.acceptsImages
    }

    private var keyFailureBinding: Binding<Bool> {
        Binding(get: { keyFailure != nil }, set: { if !$0 { keyFailure = nil } })
    }

    private var attachmentErrorBinding: Binding<Bool> {
        Binding(get: { attachmentError != nil }, set: { if !$0 { attachmentError = nil } })
    }
}
