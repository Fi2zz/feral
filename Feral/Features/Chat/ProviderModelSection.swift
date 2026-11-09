import SwiftUI

/// 当前提供商的模型区：点选模型、看那句人话说明、推理档位只对认它的模型显示。
/// 换模型立刻重新装配。宿主在切换提供商时按 `.id(provider)` 重建本区。
struct ProviderModelSection: View {
    let provider: CoachProvider
    let onModelChange: (CoachModel) -> Void

    @State private var model: CoachModel
    @State private var effort: ReasoningEffort

    init(provider: CoachProvider, onModelChange: @escaping (CoachModel) -> Void) {
        self.provider = provider
        self.onModelChange = onModelChange
        _model = State(initialValue: CoachModelStore.selected(provider: provider))
        _effort = State(initialValue: ReasoningEffortStore.selected())
    }

    var body: some View {
        Section {
            if CoachLlmConfig.isModelOverridden {
                LabeledContent("模型", value: CoachLlmConfig.model)
                Label("被环境变量 KIMI_MODEL 顶掉了，这里的点选不生效。", systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Picker("模型", selection: modelBinding) {
                    ForEach(provider.models) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .pickerStyle(.inline)
                Text(model.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                effortRow
            }
        } header: {
            Text("模型")
        } footer: {
            Text("换模型会立刻重新装配，不用重启 App。")
        }
    }

    /// 档位只对认 `reasoning_effort` 的模型开放；改完下一条消息就生效，不用重新装配。
    @ViewBuilder
    private var effortRow: some View {
        if model.acceptsReasoningEffort {
            effortControl
        } else {
            LabeledContent("推理档位", value: "不适用（该模型不认这个参数）")
        }
    }

    /// 被环境变量钉住时只显示值，免得以为在这里改有用。
    @ViewBuilder
    private var effortControl: some View {
        if CoachLlmConfig.isEffortOverridden {
            LabeledContent("推理档位", value: CoachLlmConfig.reasoningEffort.rawValue)
        } else {
            Picker("推理档位", selection: effortBinding) {
                ForEach(ReasoningEffort.allCases, id: \.self) { candidate in
                    Text(candidate.rawValue).tag(candidate)
                }
            }
        }
    }

    private var effortBinding: Binding<ReasoningEffort> {
        Binding(
            get: { effort },
            set: { picked in
                effort = picked
                ReasoningEffortStore.save(picked)
            }
        )
    }

    private var modelBinding: Binding<CoachModel> {
        Binding(
            get: { model },
            set: { picked in
                model = picked
                onModelChange(picked)
            }
        )
    }
}
