import Foundation
import Testing

@testable import Feral

@Suite("提供商与模型选择", .serialized)
struct CoachProviderTests {
    @Test("提供商三家：Kimi、DeepSeek 与 OpenCode Go")
    func offersThreeProviders() {
        #expect(CoachProvider.allCases == [.kimi, .deepseek, .openCodeGo])
    }

    @Test("没选过的时候用 Kimi")
    func defaultsToKimi() throws {
        #expect(CoachProviderStore.selected(in: try isolated()) == .kimi)
    }

    @Test("选过提供商记得住，不认识的值退回 Kimi")
    func remembersProvider() throws {
        let defaults = try isolated()
        CoachProviderStore.save(.deepseek, to: defaults)

        #expect(CoachProviderStore.selected(in: defaults) == .deepseek)
        #expect(CoachProviderStore.selected(in: try isolated()) == .kimi, "另一个域不受影响")

        defaults.set("openai", forKey: CoachProviderStore.defaultsKey)
        #expect(CoachProviderStore.selected(in: defaults) == .kimi)
    }

    @Test("三家预设模型清单：防手滑改错 ID")
    func modelCatalog() {
        #expect(CoachProvider.kimi.models.map(\.id) == ["kimi-k3", "kimi-k2.6"])
        #expect(CoachProvider.deepseek.models.map(\.id) == ["deepseek-flash"])
        #expect(CoachProvider.openCodeGo.models.map(\.id) == [
            "deepseek-v4.1-flash",
            "kimi-k3.1-pro",
            "glm-5.3",
            "qwen3.8-max",
            "minimax-m3",
            "mimo-v2.6-flash",
        ])
    }

    @Test("OpenCode Go 的端点、凭据与模型默认值")
    func openCodeGoProfile() {
        #expect(CoachProvider.openCodeGo.title == "OpenCode Go")
        #expect(CoachProvider.openCodeGo.defaultBaseUrl == "https://opencode.ai/zen/go/v1")
        #expect(CoachProvider.openCodeGo.credentialKey == "OPENCODE_API_KEY")
        #expect(CoachProvider.openCodeGo.modelDefaultsKey == "feral.opencode-go.model")
        #expect(CoachProvider.openCodeGo.fallbackModel.id == "deepseek-v4.1-flash")
    }

    @Test("OpenCode Go 每个提供商各记模型，互不干扰")
    func openCodeGoModelSelection() throws {
        let defaults = try isolated()
        #expect(CoachModelStore.selected(provider: .openCodeGo, in: defaults).id == "deepseek-v4.1-flash")

        CoachModelStore.save(CoachProvider.openCodeGo.models[1], provider: .openCodeGo, to: defaults)

        #expect(CoachModelStore.selected(provider: .openCodeGo, in: defaults).id == "kimi-k3.1-pro")
        #expect(CoachModelStore.selected(provider: .kimi, in: defaults).id == "kimi-k3", "别家的选择不受影响")
    }

    @Test("每个提供商各自记模型，互不干扰")
    func modelSelectionPerProvider() throws {
        let defaults = try isolated()
        #expect(CoachModelStore.selected(provider: .kimi, in: defaults).id == "kimi-k3")
        #expect(CoachModelStore.selected(provider: .deepseek, in: defaults).id == "deepseek-flash")

        CoachModelStore.save(CoachProvider.kimi.models[1], provider: .kimi, to: defaults)

        #expect(CoachModelStore.selected(provider: .kimi, in: defaults).id == "kimi-k2.6")
        #expect(CoachModelStore.selected(provider: .deepseek, in: defaults).id == "deepseek-flash", "别家的选择不受影响")
    }

    @Test("kimi 沿用旧键名，升级前存的 kimi-k2.6 还能读出来")
    func legacyKimiModelKeyStillReads() throws {
        let defaults = try isolated()
        defaults.set("kimi-k2.6", forKey: "feral.kimi.model")

        #expect(CoachModelStore.selected(provider: .kimi, in: defaults).id == "kimi-k2.6")
    }

    @Test("存了个不认识的模型名就退回这家默认，不崩")
    func fallsBackOnUnknownModel() throws {
        let defaults = try isolated()
        defaults.set("moonshot-v1-8k", forKey: CoachProvider.kimi.modelDefaultsKey)

        #expect(CoachModelStore.selected(provider: .kimi, in: defaults).id == "kimi-k3")
    }

    @Test("环境变量优先于点选（仅 kimi），联调时能临时顶掉")
    func environmentWinsOverPick() throws {
        let restore = pinProvider(.kimi)
        defer { restore() }
        setenv("KIMI_MODEL", "kimi-k2.6", 1)
        defer { unsetenv("KIMI_MODEL") }

        #expect(CoachLlmConfig.model == "kimi-k2.6")
        #expect(CoachLlmConfig.isModelOverridden)
    }

    @Test("选了别家之后 KIMI_MODEL 不生效，免得 mock 通道串到真服务")
    func environmentIgnoredForOtherProviders() throws {
        let restore = pinProvider(.deepseek)
        defer { restore() }
        setenv("KIMI_MODEL", "kimi-k2.6", 1)
        defer { unsetenv("KIMI_MODEL") }

        #expect(CoachLlmConfig.model == "deepseek-flash")
        #expect(CoachLlmConfig.isModelOverridden == false)
    }

    @Test("空串不算设过，别把默认模型顶掉")
    func emptyOverrideIgnored() throws {
        let restore = pinProvider(.kimi)
        defer { restore() }
        setenv("KIMI_MODEL", "", 1)
        defer { unsetenv("KIMI_MODEL") }

        #expect(CoachLlmConfig.model == CoachModelStore.selected(provider: .kimi).id)
        #expect(CoachLlmConfig.isModelOverridden == false)
    }

    @Test("K3 带 reasoning_effort=high；K2.6 不发；DeepSeek 带思考开关与档位")
    func requestOptionsPerModel() throws {
        let restore = pinProvider(.kimi)
        defer { restore() }
        setenv("KIMI_MODEL", "kimi-k3", 1)
        #expect(CoachLlmConfig.requestOptions?["reasoning_effort"]?.stringValue == "high")
        #expect(CoachLlmConfig.requestOptions?["thinking"] == nil, "不往 Kimi 发 DeepSeek 的开关")

        setenv("KIMI_MODEL", "kimi-k2.6", 1)
        #expect(CoachLlmConfig.requestOptions == nil)
        unsetenv("KIMI_MODEL")

        CoachProviderStore.save(.deepseek)
        #expect(CoachLlmConfig.requestOptions?["thinking"]?["type"]?.stringValue == "enabled")
        #expect(CoachLlmConfig.requestOptions?["reasoning_effort"]?.stringValue == "high")
    }

    @Test("档位可以临时顶掉，认不出的值退回默认")
    func effortOverride() throws {
        let restore = pinProvider(.kimi)
        defer { restore() }
        setenv("KIMI_MODEL", "kimi-k3", 1)
        setenv("KIMI_REASONING_EFFORT", "low", 1)
        defer {
            unsetenv("KIMI_MODEL")
            unsetenv("KIMI_REASONING_EFFORT")
        }
        #expect(CoachLlmConfig.requestOptions?["reasoning_effort"]?.stringValue == "low")

        setenv("KIMI_REASONING_EFFORT", "medium", 1)
        #expect(CoachLlmConfig.reasoningEffort == .high, "认不出就退回默认 high")
    }

    @Test("设置页选过的档位直接进请求，DeepSeek 也认")
    func storedEffortApplies() throws {
        let restore = pinProvider(.deepseek)
        defer { restore() }
        ReasoningEffortStore.save(.max)
        defer { UserDefaults.standard.removeObject(forKey: ReasoningEffortStore.defaultsKey) }

        #expect(CoachLlmConfig.reasoningEffort == .max)
        #expect(CoachLlmConfig.requestOptions?["reasoning_effort"]?.stringValue == "max")
    }

    @Test("环境变量顶掉设置页选过的档位（仅 kimi 联调通道）")
    func environmentEffortWinsOverStored() throws {
        let restore = pinProvider(.kimi)
        defer { restore() }
        ReasoningEffortStore.save(.max)
        defer { UserDefaults.standard.removeObject(forKey: ReasoningEffortStore.defaultsKey) }
        setenv("KIMI_REASONING_EFFORT", "low", 1)
        defer { unsetenv("KIMI_REASONING_EFFORT") }

        #expect(CoachLlmConfig.reasoningEffort == .low)
        #expect(CoachLlmConfig.isEffortOverridden)
    }

    @Test("存了个认不出的档位就退回默认 high，不崩")
    func invalidStoredEffortFallsBack() throws {
        let restore = pinProvider(.kimi)
        defer { restore() }
        UserDefaults.standard.set("ultra", forKey: ReasoningEffortStore.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: ReasoningEffortStore.defaultsKey) }

        #expect(CoachLlmConfig.reasoningEffort == .high)
    }

    @Test("默认档位是 high")
    func defaultEffortIsHigh() {
        unsetenv("KIMI_REASONING_EFFORT")
        #expect(CoachLlmConfig.reasoningEffort == .high)
        #expect(ReasoningEffort.fallback == .high)
    }

    private func isolated() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "coach-provider-tests-\(UUID().uuidString)"))
    }

    /// `CoachLlmConfig` 读的是 `.standard` 里的提供商选择：用例先把提供商钉住，
    /// 跑完还原，免得模拟器里点过的选择串进断言。
    private func pinProvider(_ provider: CoachProvider) -> () -> Void {
        let previous = UserDefaults.standard.string(forKey: CoachProviderStore.defaultsKey)
        CoachProviderStore.save(provider)
        return {
            if let previous {
                UserDefaults.standard.set(previous, forKey: CoachProviderStore.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CoachProviderStore.defaultsKey)
            }
        }
    }
}
