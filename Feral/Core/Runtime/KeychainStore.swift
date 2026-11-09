import Foundation
import Security

/// 钥匙串通用密码的读写。Key 只留在钥匙串里：不落文件、不进仓库（规格 8）。
///
/// 这个层不依赖 Swiftus，视图层（MainActor）与运行时层都能调；
/// 运行时层的 `KeychainCredentials` 在它之上再包一层凭据快照。
enum KeychainStore {
    enum Failure: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let code): "钥匙串操作失败（OSStatus \(code)）"
            }
        }
    }

    /// 取一条通用密码；不存在返回 nil，其余错误抛出来。
    static func read(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &item)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess else { throw Failure.status(code) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw Failure.status(errSecDecode)
        }
        return value
    }

    /// 写入或覆盖一条通用密码，空串视为删除。
    static func write(_ value: String, service: String, account: String) throws {
        guard !value.isEmpty else {
            try delete(service: service, account: account)
            return
        }
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let code = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        if code == errSecDuplicateItem {
            let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
            guard update == errSecSuccess else { throw Failure.status(update) }
            return
        }
        guard code == errSecSuccess else { throw Failure.status(code) }
    }

    static func delete(service: String, account: String) throws {
        let code = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard code == errSecSuccess || code == errSecItemNotFound else {
            throw Failure.status(code)
        }
    }

    /// 尾部几位，用来在界面上确认「现在用的是哪一把 Key」，不显示明文。
    static func fingerprint(_ value: String) -> String {
        String(value.suffix(4))
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
