import SwiftUI

/// 智能搜索的 Key 区：Tavily / Exa / Brave，任填其一即可；DuckDuckGo 免 Key 兜底。
struct SearchKeySection: View {
    var body: some View {
        Section {
            SearchKeyRow(title: "Tavily", account: SearchKeyStore.tavilyKey)
            SearchKeyRow(title: "Exa", account: SearchKeyStore.exaKey)
            SearchKeyRow(title: "Brave", account: SearchKeyStore.braveKey)
        } header: {
            Text("智能搜索")
        } footer: {
            Text("按 Tavily → Exa → Brave 的顺序使用；都没填时用 DuckDuckGo 免 Key 兜底。Key 只存钥匙串。")
        }
    }
}

private struct SearchKeyRow: View {
    let title: String
    let account: String

    @State private var value = ""
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 与 LLM Key 一致：普通 TextField 才能用第三方输入法和长按粘贴，
            // 明文靠 privacySensitive() 在切后台/截图时遮挡。
            TextField("\(title) API Key", text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()

            HStack {
                if saved, let fingerprint = SearchKeyStore.fingerprint(account: account) {
                    Label("已保存（尾部 \(fingerprint)）", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if saved {
                    Button("清除", role: .destructive, action: clear)
                        .font(.caption)
                }
                Button("保存", action: save)
                    .font(.caption)
                    .disabled(trimmed.isEmpty)
            }
        }
        .onAppear { saved = SearchKeyStore.isSaved(account: account) }
        .alert("保存失败", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var trimmed: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        do {
            try SearchKeyStore.save(trimmed, account: account)
            value = ""
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clear() {
        do {
            try SearchKeyStore.clear(account: account)
            saved = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}
