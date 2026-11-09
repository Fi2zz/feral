import Foundation

/// 各家 API Key 的存取门面。界面（MainActor）用它写钥匙串，
/// 运行时（`@ContextTreeActor`）自己另有一份 `KeychainCredentials` 读同一把 Key。
enum CoachKeyStore {
    /// 这家提供商的钥匙串里有没有可用的 Key。
    static func isSaved(provider: CoachProvider) -> Bool {
        (try? current(provider: provider))?.isEmpty == false
    }

    /// 已保存的 Key，只用来显示尾部几位，明文不进界面。
    static func fingerprint(provider: CoachProvider) -> String? {
        guard let key = try? current(provider: provider), !key.isEmpty else { return nil }
        return KeychainStore.fingerprint(key)
    }

    /// 写入一把新 Key。空串等价于清除。
    static func save(_ key: String, provider: CoachProvider) throws {
        try KeychainStore.write(
            key.trimmingCharacters(in: .whitespacesAndNewlines),
            service: provider.keychainService,
            account: provider.credentialKey
        )
    }

    static func clear(provider: CoachProvider) throws {
        try KeychainStore.delete(
            service: provider.keychainService,
            account: provider.credentialKey
        )
    }

    private static func current(provider: CoachProvider) throws -> String? {
        try KeychainStore.read(
            service: provider.keychainService,
            account: provider.credentialKey
        )
    }
}
