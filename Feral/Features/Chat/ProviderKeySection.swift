import SwiftUI

/// 当前提供商的 API Key 区：输入、保存、清除。Key 只进钥匙串，明文不落别处。
/// 宿主在切换提供商时按 `.id(provider)` 重建本区，输入框跟着清空。
struct ProviderKeySection: View {
    let provider: CoachProvider
    let onSave: (String) -> Void
    let onClear: () -> Void

    @State private var key = ""

    var body: some View {
        Section {
            keyField
            Button("保存 Key") { onSave(trimmed) }
                .disabled(trimmed.isEmpty)
            if saved {
                Button("清除已保存的 Key", role: .destructive, action: onClear)
            }
        } header: {
            Text("\(provider.title) API Key")
        } footer: {
            Text(footerText)
        }
    }

    /// 刻意用普通 `TextField` 而不是 `SecureField`。
    ///
    /// iOS 的安全输入框（`isSecureTextEntry`）是系统行为，不是 SwiftUI 的选择：
    /// 它不弹第三方输入法，也拦掉长按粘贴。Key 有五十来字符，记不住也打不动，
    /// 两条路都堵死就只能靠手抄。用普通输入框换回输入法和粘贴，
    /// 靠 `.privacySensitive()` 挡住切后台和截图时的明文——key 本身仍然只存钥匙串。
    private var keyField: some View {
        TextField("sk-…", text: $key)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .privacySensitive()
    }

    private var saved: Bool {
        CoachKeyStore.isSaved(provider: provider)
    }

    private var footerText: String {
        let stored = saved ? "钥匙串里已保存一把 Key（尾部 \(CoachKeyStore.fingerprint(provider: provider) ?? "…")）。" : ""
        return stored + provider.profile.keyConsoleHint + "支持第三方输入法与粘贴；输入时不遮挡，但切后台和截图会被遮住。保存后输入框清空。"
    }

    private var trimmed: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
