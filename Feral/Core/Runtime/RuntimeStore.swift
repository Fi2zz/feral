import Foundation
import SwiftUI
import SwiftusCredentials
import SwiftusLLM
import SwiftusSearch

/// 视图侧唯一能碰运行时的入口：装配在 `ContextTreeActor` 上做，
/// 状态回写留在 MainActor。`Task` 写全名是防将来引入伞产品时被 `SwiftusTasks.Task` 遮蔽。
@MainActor
@Observable
final class RuntimeStore {
    enum State: Equatable {
        case idle
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .idle: "未装配"
            case .ready: "已就绪"
            case .failed(let reason): "装配失败：\(reason)"
            }
        }
    }

    private(set) var state: State = .idle
    /// 钥匙串里有没有 Key。界面据此显示「已保存」还是「未配置」。
    private(set) var hasKey = false
    /// 已保存 Key 的尾部几位，方便确认换没换成功。
    private(set) var keyFingerprint: String?
    /// 持有上下文树本身：装配完不能丢，释放即凭据 close、LLM 退订。
    private var runtime: FeralRuntime?

    func start() {
        refreshKeyState()
        guard case .idle = state else { return }
        boot()
    }

    /// 改完 Key 后重来一遍装配，不用重启 App。
    func restart() {
        runtime = nil
        state = .idle
        refreshKeyState()
        boot()
    }

    func refreshKeyState() {
        let provider = CoachProviderStore.selected()
        hasKey = CoachKeyStore.isSaved(provider: provider)
        keyFingerprint = CoachKeyStore.fingerprint(provider: provider)
    }

    /// 问一句。运行时装配失败、Key 缺失都原样抛给界面，不静默吞掉。
    func ask(
        question: String,
        conversation: [LlmMessage],
        sessionID: UUID,
        images: [LlmImage] = [],
        includesSearchResults: Bool = false
    ) async throws -> String {
        let stream = try await askStream(
            question: question,
            conversation: conversation,
            sessionID: sessionID,
            images: images,
            includesSearchResults: includesSearchResults
        )
        var answer = ""
        for try await event in stream {
            if case .textDelta(let delta) = event { answer += delta }
        }
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 流式问一句。装配没完成就直接抛，不返回一个只会立刻失败的空流。
    /// `await` 是因为真正建流的那层在 `@ContextTreeActor` 上。
    func askStream(
        question: String,
        conversation: [LlmMessage],
        sessionID: UUID,
        images: [LlmImage] = [],
        includesSearchResults: Bool = false
    ) async throws -> AsyncThrowingStream<LlmStreamEvent, Error> {
        guard let runtime else {
            throw RuntimeError.notBootstrapped
        }
        return await runtime.askStream(
            system: ChatPrompt.system(today: Date(), includesSearchResults: includesSearchResults),
            conversation: conversation,
            question: question,
            images: images,
            headers: CoachLlmConfig.provider.sessionHeaders(sessionID: sessionID)
        )
    }

    /// 联网搜索。给 ChatStore 在发送前拼上下文用。
    func search(_ query: String, limit: Int = 5) async throws -> [SearchResult] {
        guard let runtime else {
            throw RuntimeError.notBootstrapped
        }
        return try await runtime.search(query, limit: limit)
    }

    enum RuntimeError: LocalizedError {
        case notBootstrapped

        var errorDescription: String? {
            "运行时还没装好。先在下面填 API Key，再点「重新装配」。"
        }
    }

    private func boot() {
        // 本闭包已继承 MainActor，写 state 无需再 hop。
        _Concurrency.Task { [weak self] in
            let booted: FeralRuntime
            do {
                booted = try await FeralRuntime.bootstrap()
            } catch {
                self?.attachFailure(error)
                return
            }
            self?.attach(booted)
        }
    }

    private func attach(_ runtime: FeralRuntime) {
        self.runtime = runtime
        state = .ready
    }

    private func attachFailure(_ error: any Error) {
        runtime = nil
        state = .failed(Self.reason(error))
    }

    /// Swiftus 的异常自带中文原因，`localizedDescription` 只会给出「error 1」这类无信息文本。
    private static func reason(_ error: any Error) -> String {
        (error as? CredentialsException)?.message ?? String(describing: error)
    }
}
