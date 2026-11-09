import Foundation

/// 搜索提供商 Key 的存取门面。Key 只进钥匙串，不落文件。
enum SearchKeyStore {
    static let service = "com.fi2zz.feral.search"

    static let tavilyKey = "TAVILY_API_KEY"
    static let exaKey = "EXA_API_KEY"
    static let braveKey = "BRAVE_API_KEY"

    static let allKeys = [tavilyKey, exaKey, braveKey]

    static func isSaved(account: String) -> Bool {
        (try? KeychainStore.read(service: service, account: account))?.isEmpty == false
    }

    static func fingerprint(account: String) -> String? {
        guard let key = try? KeychainStore.read(service: service, account: account),
              !key.isEmpty else { return nil }
        return KeychainStore.fingerprint(key)
    }

    static func save(_ value: String, account: String) throws {
        try KeychainStore.write(
            value.trimmingCharacters(in: .whitespacesAndNewlines),
            service: service,
            account: account
        )
    }

    static func clear(account: String) throws {
        try KeychainStore.delete(service: service, account: account)
    }

    /// 当前可用的 Key，键名就是 SwiftusSearch 的凭据键。
    static func savedKeys() -> [String: String] {
        var keys: [String: String] = [:]
        for account in allKeys {
            guard let value = try? KeychainStore.read(service: service, account: account),
                  !value.isEmpty else { continue }
            keys[account] = value
        }
        return keys
    }
}
