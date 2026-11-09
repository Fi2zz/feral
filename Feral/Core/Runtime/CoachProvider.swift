import Foundation

/// 对话可用的 LLM 提供商。两家都是 OpenAI 兼容协议，运行时统一走
/// `OpenAiCompatibleProvider`，差异全部收敛在 `profile` 这张表里。
enum CoachProvider: String, CaseIterable, Identifiable, Sendable {
    case kimi
    case deepseek

    var id: String { rawValue }

    // REASON: 静态映射表 —— 提供商元数据天然是一张表，一处说清两家差异，比散开的 switch 易读。
    var profile: CoachProviderProfile {
        switch self {
        case .kimi: .kimi
        case .deepseek: .deepseek
        }
    }

    var title: String { profile.title }
    var defaultBaseUrl: String { profile.defaultBaseUrl }
    var credentialKey: String { profile.credentialKey }
    var keychainService: String { profile.keychainService }
    var modelDefaultsKey: String { profile.modelDefaultsKey }
    var models: [CoachModel] { profile.models }
    var fallbackModel: CoachModel { profile.models[0] }

    /// 环境变量覆盖（联调 mock）只对 Kimi 开放，其余两家没有这条通道。
    var honorsEnvironmentOverride: Bool { self == .kimi }
}

/// 一家提供商的全部差异：界面标题、端点、凭据键名、钥匙串 service、模型清单。
struct CoachProviderProfile: Sendable {
    let title: String
    /// 设置页 Key 区的 footer：去哪个控制台拿 Key。
    let keyConsoleHint: String
    let defaultBaseUrl: String
    /// 凭据源（钥匙串快照）里的键名。
    let credentialKey: String
    /// 钥匙串 service。kimi 沿用旧的 Moonshot 名字，老用户的 Key 无感保留。
    let keychainService: String
    /// 各自记住各自选过的模型；kimi 沿用旧键名，升级前存的选择不丢。
    let modelDefaultsKey: String
    let models: [CoachModel]
}

extension CoachProviderProfile {
    static let kimi = CoachProviderProfile(
        title: "Kimi（月之暗面）",
        keyConsoleHint: "去 platform.moonshot.cn 的「API Key 管理」拿一把。",
        defaultBaseUrl: "https://api.moonshot.cn/v1",
        credentialKey: "KIMI_API_KEY",
        keychainService: "com.fi2zz.feral.moonshot",
        modelDefaultsKey: "feral.kimi.model",
        models: [
            CoachModel(id: "kimi-k3", title: "Kimi K3", note: "旗舰，1M 上下文，适合长文与复杂问题", acceptsReasoningEffort: true),
            CoachModel(id: "kimi-k2.6", title: "Kimi K2.6", note: "通用，256K 上下文，够用且更省"),
        ]
    )

    static let deepseek = CoachProviderProfile(
        title: "DeepSeek",
        keyConsoleHint: "去 platform.deepseek.com 的「API keys」拿一把。",
        defaultBaseUrl: "https://api.deepseek.com/v1",
        credentialKey: "DEEPSEEK_API_KEY",
        keychainService: "com.fi2zz.feral.deepseek",
        modelDefaultsKey: "feral.deepseek.model",
        models: [
            CoachModel(
                id: "deepseek-flash",
                title: "DeepSeek V4.1 Flash",
                note: "快且省，原生多模态，支持思考模式",
                acceptsReasoningEffort: true,
                acceptsThinkingToggle: true
            ),
        ]
    )
}

/// 一个可选模型。`id` 就是发给服务端的模型名。
struct CoachModel: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    /// 选模型时那句人话，标明上下文量级或开通前提。
    let note: String
    /// 能不能收请求顶层的 `reasoning_effort`。官方文档明说各模型参数配置不同，
    /// 不认这个字段的模型一个多余字段都不发。
    var acceptsReasoningEffort = false
    /// 要不要发请求顶层的 `thinking: {"type": "enabled"}`（DeepSeek 思考模式开关）。
    var acceptsThinkingToggle = false
}

/// 提供商选择的持久化。不是秘密，放 UserDefaults 就够；API Key 仍然只在钥匙串。
enum CoachProviderStore {
    static let defaultsKey = "feral.coach.provider"

    static func selected(in defaults: UserDefaults = .standard) -> CoachProvider {
        guard let raw = defaults.string(forKey: defaultsKey),
              let provider = CoachProvider(rawValue: raw) else {
            return .kimi
        }
        return provider
    }

    static func save(_ provider: CoachProvider, to defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: defaultsKey)
    }
}

/// 每个提供商各自记住选中的模型；存了个不认识的名字就退回这家默认，不崩。
enum CoachModelStore {
    static func selected(provider: CoachProvider, in defaults: UserDefaults = .standard) -> CoachModel {
        guard let raw = defaults.string(forKey: provider.modelDefaultsKey),
              let model = provider.models.first(where: { $0.id == raw }) else {
            return provider.fallbackModel
        }
        return model
    }

    static func save(_ model: CoachModel, provider: CoachProvider, to defaults: UserDefaults = .standard) {
        defaults.set(model.id, forKey: provider.modelDefaultsKey)
    }
}
