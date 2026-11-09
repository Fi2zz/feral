import Foundation

/// 搜索提供商 Key 的存取门面。Key 只进钥匙串，不落文件。
///
/// MCP 版只接 Exa：不填 Key 走 Exa 免 Key，填了用用户自己的 Exa 额度。
enum SearchKeyStore {
    static let service = "com.fi2zz.feral.search"
    static let exaKey = "EXA_API_KEY"
    static let parallelKey = "PARALLEL_API_KEY"

    static func isSaved(account: String = exaKey) -> Bool {
        savedKey(account: account) != nil
    }

    static func savedKey(account: String = exaKey) -> String? {
        guard let key = try? KeychainStore.read(service: service, account: account),
              !key.isEmpty else { return nil }
        return key
    }

    static func fingerprint(account: String = exaKey) -> String? {
        savedKey(account: account).map(KeychainStore.fingerprint)
    }

    static func save(_ value: String, account: String = exaKey) throws {
        try KeychainStore.write(
            value.trimmingCharacters(in: .whitespacesAndNewlines),
            service: service,
            account: account
        )
    }

    static func clear(account: String = exaKey) throws {
        try KeychainStore.delete(service: service, account: account)
    }
}
