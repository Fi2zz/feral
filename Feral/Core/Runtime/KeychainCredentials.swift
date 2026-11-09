import Foundation
import SwiftusCore
import SwiftusCredentials

/// 钥匙串凭据来源：可写，`update` 落到钥匙串并推送变更（SwiftusCredentials 契约）。
///
/// 替掉早先的 `FileCredentials` 沙盒文件：Key 不再以明文躺在 Application Support。
/// 视图层写钥匙串 → 运行时 `refresh()` 重拉快照 → LLM wire 层拿到新 Key。
@ContextTreeActor
final class KeychainCredentials: Credentials {
    private let service: String
    private let credentialKey: String
    private let snapshot = CredentialSnapshot()

    init(service: String, credentialKey: String) {
        self.service = service
        self.credentialKey = credentialKey
    }

    var keys: [String] { snapshot.keys }

    func get(_ key: String) -> Credential? { snapshot.get(key) }

    func update(_ key: String, _ value: String) async throws {
        try KeychainStore.write(value, service: service, account: key)
        snapshot.update(Credential(key: key, value: value))
    }

    @discardableResult
    func addChangeListener(_ body: @escaping @ContextTreeActor (Credential) -> Void) -> Int {
        snapshot.addChangeListener(body)
    }

    @discardableResult
    func removeChangeListener(_ token: Int) -> Bool {
        snapshot.removeChangeListener(token)
    }

    /// 从钥匙串重拉快照。钥匙串里没有就清空，让 LLM 装配按「缺凭据」失败。
    ///
    /// 例外：端点被环境变量指到本机假服务时补一把占位 Key——假服务不校验 Key，
    /// 这样 `make run-mock` 在干净的模拟器上也能直接跑通，不必先手输一把假 key。
    /// 环境变量覆盖只对 Kimi 开放，所以这里认 `CoachLlmConfig.isOverridden` 就够。
    func refresh() async throws {
        let entries = [credentialKey].compactMap { key -> Credential? in
            guard let value = try? KeychainStore.read(service: service, account: key),
                  !value.isEmpty else { return nil }
            return Credential(key: key, value: value)
        }
        if entries.isEmpty, CoachLlmConfig.isOverridden {
            let placeholder = Credential(key: credentialKey, value: "mock-key")
            snapshot.refreshSnapshot([placeholder.key: placeholder])
            return
        }
        snapshot.refreshSnapshot(Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) }))
    }

    func close() {
        snapshot.close()
    }
}
