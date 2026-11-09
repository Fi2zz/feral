import Foundation
import SwiftusCore
import SwiftusLLM

/// 对话 LLM 的端点与模型配置，全部按当前选中的提供商取值。
/// 环境变量覆盖是 Kimi 专属的联调通道（`make run-mock`），其余两家没有。
enum CoachLlmConfig {
    static var provider: CoachProvider {
        CoachProviderStore.selected()
    }

    static var baseUrl: String {
        overridden("KIMI_BASE_URL") ?? provider.defaultBaseUrl
    }

    /// 模型：kimi 联调可用环境变量顶掉 > 设置页点选的 > 默认。
    static var model: String {
        overridden("KIMI_MODEL") ?? CoachModelStore.selected(provider: provider).id
    }

    /// 推理档位：联调用环境变量顶掉 > 设置页选过的 > 默认 high。只对认这个参数的模型有意义。
    static var reasoningEffort: ReasoningEffort {
        if let raw = overridden("KIMI_REASONING_EFFORT"),
           let effort = ReasoningEffort(rawValue: raw) {
            return effort
        }
        return ReasoningEffortStore.selected()
    }

    /// 档位被环境变量钉住时设置页的选择器不生效，界面上只显示值，免得以为改了有用。
    static var isEffortOverridden: Bool {
        overridden("KIMI_REASONING_EFFORT") != nil
    }

    /// 端点或模型被环境变量改过：界面上要能看出来，免得以为在跟真服务说话。
    static var isOverridden: Bool {
        isBaseUrlOverridden || isModelOverridden
    }

    static var isBaseUrlOverridden: Bool {
        overridden("KIMI_BASE_URL") != nil
    }

    static var isModelOverridden: Bool {
        overridden("KIMI_MODEL") != nil
    }

    /// 要并进请求体顶层的字段。按当前模型的能力位组，一个多余字段都不发。
    static var requestOptions: [String: JSONValue]? {
        guard let current = provider.models.first(where: { $0.id == model }) else {
            return nil
        }
        var options: [String: JSONValue] = [:]
        if current.acceptsThinkingToggle {
            options["thinking"] = .object(["type": .string("enabled")])
        }
        if current.acceptsReasoningEffort {
            options["reasoning_effort"] = .string(reasoningEffort.rawValue)
        }
        return options.isEmpty ? nil : options
    }

    static func openAi() -> OpenAiConfig {
        var config = OpenAiConfig(name: provider.rawValue, baseUrl: baseUrl, model: model)
        config.credentialKey = provider.credentialKey
        return config
    }

    /// 空串当作没设，免得 `KIMI_BASE_URL=` 反而把默认端点顶掉。
    private static func overridden(_ key: String) -> String? {
        guard provider.honorsEnvironmentOverride,
              let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { return nil }
        return value
    }
}

/// 推理档位。Kimi K3 与 DeepSeek 都支持 `low` / `high` / `max`，Kimi 官方默认是 `max`。
///
/// 这里的默认取 `high`：日常对话满档推理收益有限，却要等更久、花更多 token。认这个参数的模型见
/// `CoachModel.acceptsReasoningEffort`。
enum ReasoningEffort: String, CaseIterable, Sendable {
    case low
    case high
    case max

    static let fallback: ReasoningEffort = .high
}

/// 设置页选过的推理档位。不是秘密，放 UserDefaults；认 effort 的模型共用这一档，
/// 存了个认不出的值就退回默认，不崩。
enum ReasoningEffortStore {
    static let defaultsKey = "feral.coach.reasoning.effort"

    static func selected(in defaults: UserDefaults = .standard) -> ReasoningEffort {
        guard let raw = defaults.string(forKey: defaultsKey),
              let effort = ReasoningEffort(rawValue: raw) else {
            return .fallback
        }
        return effort
    }

    static func save(_ effort: ReasoningEffort, to defaults: UserDefaults = .standard) {
        defaults.set(effort.rawValue, forKey: defaultsKey)
    }
}
