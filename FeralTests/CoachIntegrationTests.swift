import Foundation
import SwiftusLLM
import Testing

@testable import Feral

/// 真打到假服务上的联调用例（运行时层：装配、请求、SSE、错误透传）。
/// ChatStore 层的联调在 ChatStoreIntegrationTests；假服务探针在 MockKimiServer.swift。
///
/// 只在假服务起着的时候跑（`make test-llm` 会先把它拉起来），平时 `make test`
/// 自动跳过，不因为「本机没起服务」而红。
@Suite("对话联调", .enabled(if: MockKimiServer.reachable), .serialized)
@MainActor
struct CoachIntegrationTests {
    @Test("走完整链路：钥匙串 → provider → SSE → 回答")
    func answersThroughTheWire() async throws {
        let runtime = try await bootstrapAgainstMock()

        let answer = try await runtime.ask(
            system: ChatPrompt.system(),
            conversation: [],
            question: "帮我理一下今天的安排"
        )

        // 假服务把收到的东西回述一遍，所以这几条同时证明了「发出去的是什么」。
        #expect(answer.contains("（mock）收到了"))
        #expect(answer.contains("帮我理一下今天的安排"))
    }

    @Test("带上历史对话再问一轮")
    func carriesConversationHistory() async throws {
        let runtime = try await bootstrapAgainstMock()

        let answer = try await runtime.ask(
            system: ChatPrompt.system(),
            conversation: [
                LlmMessage("user", "帮我想个标题"),
                LlmMessage("assistant", "给你三个方向。"),
            ],
            question: "第二个再展开说说"
        )

        #expect(answer.contains("历史消息 2 条"))
    }

    @Test("服务端报错要把原文和状态码带出来，不许静默成功")
    func surfacesServerErrors() async throws {
        let runtime = try await bootstrapAgainstMock(pathSuffix: "/unauthorized")

        do {
            _ = try await runtime.ask(system: "s", conversation: [], question: "在吗")
            Issue.record("服务端返回 401 时不该当成成功")
        } catch {
            let reason = ErrorText.reason(error)
            #expect(reason.contains("不认"), "要把服务端给的原因带出来：\(reason)")
            #expect(reason.contains("401"))
        }
    }

    @Test("流式：增量真的分片到达，拼起来是完整回答")
    func streamsDeltas() async throws {
        let runtime = try await bootstrapAgainstMock()

        let stream = await runtime.askStream(system: "s", conversation: [], question: "在吗")
        var deltas: [String] = []
        var reasoning: [String] = []
        for try await event in stream {
            switch event {
            case .textDelta(let delta): deltas.append(delta)
            case .reasoningDelta(let delta): reasoning.append(delta)
            default: break
            }
        }

        #expect(deltas.count > 1, "要边生成边到，不能一次给完")
        #expect(deltas.joined().contains("（mock）收到了"))
        #expect(reasoning.joined().contains("理一下思路"), "思考增量也要到（DeepSeek 思考模式同链路）")
    }

    @Test("K3 的请求真的带上了 reasoning_effort=high")
    func carriesEffortForK3() async throws {
        setenv("KIMI_MODEL", "kimi-k3", 1)
        defer { unsetenv("KIMI_MODEL") }
        let runtime = try await bootstrapAgainstMock()

        let answer = try await runtime.ask(system: "s", conversation: [], question: "在吗")

        #expect(answer.contains("reasoning_effort：high"))
    }

    @Test("K2.6 的请求里没有 reasoning_effort")
    func omitsEffortForK26() async throws {
        setenv("KIMI_MODEL", "kimi-k2.6", 1)
        defer { unsetenv("KIMI_MODEL") }
        let runtime = try await bootstrapAgainstMock()

        let answer = try await runtime.ask(system: "s", conversation: [], question: "在吗")

        #expect(answer.contains("reasoning_effort：（无）"))
    }

    private func bootstrapAgainstMock(pathSuffix: String = "") async throws -> FeralRuntime {
        // 这次装配会读环境变量，所以先指过去；App 里的默认端点不受影响。
        setenv("KIMI_BASE_URL", MockKimiServer.baseUrl + pathSuffix, 1)
        defer { unsetenv("KIMI_BASE_URL") }
        let restoreProvider = MockKimiServer.pinKimiProvider()
        defer { restoreProvider() }
        let restoreKey = MockKimiServer.stashKey()
        defer { restoreKey() }
        try CoachKeyStore.save("sk-mock", provider: .kimi)
        return try await FeralRuntime.bootstrap()
    }
}
