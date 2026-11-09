import Foundation
import SwiftData

/// 对话角色。v1 只读，模型不写库。
enum ChatRole: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
}

@Model
final class KimiChatMessage {
    var id: UUID = UUID()
    var role: ChatRole = ChatRole.user
    var content: String = ""
    var createdAt: Date = Date()
    /// 属于哪一次会话。开新会话就是换一个 id：旧消息照样看得见，但不进模型上下文。
    var conversationID: UUID = KimiChatMessage.legacyConversation

    /// 这条消息携带的附件；删消息时一起删。
    @Relationship(deleteRule: .cascade, inverse: \ChatAttachment.message)
    var attachments: [ChatAttachment] = []

    /// 这个字段是后加的，早先的消息没有它。给一个固定值，让它们归到同一次会话里，
    /// 而不是每条各自成为一次新会话。
    static let legacyConversation = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = Date(),
        conversationID: UUID = KimiChatMessage.legacyConversation
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.conversationID = conversationID
    }
}
