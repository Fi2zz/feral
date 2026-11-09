import Foundation
import SwiftusCore
import SwiftusCredentials
import SwiftusLLM
import SwiftusSearch

/// 上下文树的持有者。`Context` 与它的成员都在 `@ContextTreeActor` 上，
/// 视图层只能经 `RuntimeStore` 跨 actor 调用（docs/ios-接入指南.md 坑 ②）。
@ContextTreeActor
final class FeralRuntime {
    let context: Context
    private let credentials: any Credentials
    private let provider: any LlmProvider

    /// 装配：凭据（钥匙串）→ 校验 Key → LLM wire 层。整条链随 `context` 释放。
    /// 提供商在装配时定死：设置页换了提供商或模型就走 `RuntimeStore.restart()` 重来一遍。
    static func bootstrap() async throws -> FeralRuntime {
        let context = Context.root(name: "feral")
        let source = KeychainCredentials(
            service: CoachLlmConfig.provider.keychainService,
            credentialKey: CoachLlmConfig.provider.credentialKey
        )
        let credentials = try provideCredentials(context, credentials: source)
        try await credentials.refresh()
        _ = try credentials.require(CoachLlmConfig.provider.credentialKey)
        let provider = OpenAiCompatibleProvider(config: CoachLlmConfig.openAi(), credentials: credentials)
        return FeralRuntime(context: context, credentials: credentials, provider: provider)
    }

    private init(context: Context, credentials: any Credentials, provider: any LlmProvider) {
        self.context = context
        self.credentials = credentials
        self.provider = provider
    }

    /// 问一句。不传 tools：对话只读，模型没有写数据的手段。
    func ask(
        system: String,
        conversation: [LlmMessage],
        question: String,
        images: [LlmImage] = [],
        headers: [String: String] = [:]
    ) async throws -> String {
        let result = try await provider.chat(
            chatRequest(
                system: system,
                conversation: conversation,
                question: question,
                images: images,
                headers: headers
            )
        )
        return result.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 流式问一句：正文和思考过程都是增量，交给调用方边收边渲染。
    func askStream(
        system: String,
        conversation: [LlmMessage],
        question: String,
        images: [LlmImage] = [],
        headers: [String: String] = [:]
    ) -> AsyncThrowingStream<LlmStreamEvent, Error> {
        provider.chatStream(
            chatRequest(
                system: system,
                conversation: conversation,
                question: question,
                images: images,
                headers: headers
            )
        )
    }

    /// 用已保存的搜索 Key 跑一次联网搜索；DuckDuckGo 永远免 Key 兜底。
    func search(_ query: String, limit: Int = 5) async throws -> [SearchResult] {
        let credentials = InMemoryCredentials(initial: SearchKeyStore.savedKeys())
        defer { credentials.close() }
        let built = buildSearchProviders(
            order: kDefaultSearchOrder,
            credentials: credentials,
            session: .shared
        )
        let service = SearchService(statuses: built.statuses)
        for provider in built.providers {
            service.register(provider)
        }
        return try await service.search(query, limit: limit)
    }

    private func chatRequest(
        system: String,
        conversation: [LlmMessage],
        question: String,
        images: [LlmImage] = [],
        headers: [String: String] = [:]
    ) -> LlmRequest {
        var user = LlmMessage("user", question)
        user.images = images
        return LlmRequest(
            messages: [LlmMessage("system", system)] + conversation + [user],
            options: CoachLlmConfig.requestOptions,
            headers: headers.isEmpty ? nil : headers
        )
    }
}
