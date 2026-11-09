import Foundation
import SwiftData

/// 把输入条里的附件落到消息上。
@MainActor
enum AttachmentStore {
    static func persist(
        _ pending: [PendingAttachment],
        on message: KimiChatMessage,
        in context: ModelContext
    ) {
        for item in pending {
            let attachment: ChatAttachment
            switch item {
            case .image(_, let data, let mimeType):
                attachment = ChatAttachment(
                    kind: .image,
                    fileName: "图片",
                    mimeType: mimeType,
                    imageData: data
                )
            case .textFile(_, let name, let text):
                attachment = ChatAttachment(
                    kind: .textFile,
                    fileName: name,
                    mimeType: "text/plain",
                    textData: Data(text.utf8)
                )
            }
            context.insert(attachment)
            // 设置反向关系即可，SwiftData 会把它同步进 message.attachments。
            attachment.message = message
        }
    }
}
