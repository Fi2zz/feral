import Foundation
import SwiftData
import UIKit

/// 消息附件：纯文本文件或图片。
enum AttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
    case textFile
}

@Model
final class ChatAttachment {
    var id: UUID = UUID()
    var kind: AttachmentKind = AttachmentKind.textFile
    var fileName: String = ""
    var mimeType: String = ""
    /// 文本文件正文（UTF-8 字节，外部存储避免撑大 SQLite）。
    @Attribute(.externalStorage) var textData: Data?
    /// 图片字节（发送前已压缩）。
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date = Date()
    var message: KimiChatMessage?

    init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        fileName: String,
        mimeType: String = "",
        textData: Data? = nil,
        imageData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.textData = textData
        self.imageData = imageData
        self.createdAt = createdAt
    }

    /// 文本正文。
    var text: String {
        guard let textData else { return "" }
        return String(decoding: textData, as: UTF8.self)
    }

    /// 图片缩略图用的 UIImage。
    var image: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }
}
