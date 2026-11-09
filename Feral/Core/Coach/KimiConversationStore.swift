import Foundation

/// 当前会话。开新会话就是把这里换成一个新 id——旧消息还在库里（界面上也看得到），
/// 但不再作为历史发给模型，所以每次请求的上下文回到最省的状态（规格 8 的上下文注入
/// 只带最近几轮）。
enum KimiConversationStore {
    static let defaultsKey = "feral.kimi.conversation"

    /// 没有记录时用「遗留会话」那个固定 id，让升级前的消息继续算作当前会话。
    static func current(in defaults: UserDefaults = .standard) -> UUID {
        guard let raw = defaults.string(forKey: defaultsKey),
              let id = UUID(uuidString: raw) else {
            return KimiChatMessage.legacyConversation
        }
        return id
    }

    /// 切换当前会话：历史会话点进去接着聊，也是从这里走。
    static func select(_ id: UUID, in defaults: UserDefaults = .standard) {
        defaults.set(id.uuidString, forKey: defaultsKey)
    }

    /// 开一次新会话，返回新 id。
    @discardableResult
    static func startNew(in defaults: UserDefaults = .standard) -> UUID {
        let id = UUID()
        select(id, in: defaults)
        return id
    }
}
