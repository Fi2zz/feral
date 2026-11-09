import SwiftUI

/// 提供商、API Key、模型与运行时状态。保存后立刻重新装配，状态行会跟着变。
struct CoachSettingsSheet: View {
    let state: String
    let onSave: (String, CoachProvider) -> Void
    let onClear: (CoachProvider) -> Void
    let onProviderChange: (CoachProvider) -> Void
    let onModelChange: (CoachModel) -> Void
    let onReboot: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var provider: CoachProvider

    init(
        state: String,
        onSave: @escaping (String, CoachProvider) -> Void,
        onClear: @escaping (CoachProvider) -> Void,
        onProviderChange: @escaping (CoachProvider) -> Void,
        onModelChange: @escaping (CoachModel) -> Void,
        onReboot: @escaping () -> Void
    ) {
        self.state = state
        self.onSave = onSave
        self.onClear = onClear
        self.onProviderChange = onProviderChange
        self.onModelChange = onModelChange
        self.onReboot = onReboot
        _provider = State(initialValue: CoachProviderStore.selected())
    }

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                // .id(provider)：换提供商时整块重建，Key 输入框与模型点选回到那一家自己的值。
                ProviderKeySection(provider: provider, onSave: save, onClear: clear)
                    .id(provider)
                ProviderModelSection(provider: provider, onModelChange: onModelChange)
                    .id(provider)
                runtimeSection
                SearchKeySection()
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("好") { dismiss() }
                }
            }
        }
    }

    // MARK: - 提供商

    private var providerSection: some View {
        Section {
            Picker("提供商", selection: providerBinding) {
                ForEach(CoachProvider.allCases) { candidate in
                    Text(candidate.title).tag(candidate)
                }
            }
        } footer: {
            Text("换提供商立刻重新装配，不用重启 App；各家的 Key 与模型选择分别保存。")
        }
    }

    private var providerBinding: Binding<CoachProvider> {
        Binding(
            get: { provider },
            set: { picked in
                provider = picked
                onProviderChange(picked)
            }
        )
    }

    // MARK: - 运行时

    private var runtimeSection: some View {
        Section("Swiftus 运行时") {
            LabeledContent("状态", value: state)
            LabeledContent("端点", value: CoachLlmConfig.baseUrl)
            if CoachLlmConfig.isBaseUrlOverridden {
                Label("已被环境变量指到本机服务，不是真服务端。", systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("重新装配", action: reboot)
        }
    }

    private func save(_ key: String) {
        onSave(key, provider)
        dismiss()
    }

    private func clear() {
        onClear(provider)
        dismiss()
    }

    private func reboot() {
        onReboot()
        dismiss()
    }
}
