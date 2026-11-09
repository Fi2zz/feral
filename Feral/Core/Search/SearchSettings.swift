import Foundation

/// 「智能搜索」开关的持久化。
enum SearchSettings {
    static let defaultsKey = "feral.search.enabled"

    static func enabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? false
    }

    static func save(enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }
}
