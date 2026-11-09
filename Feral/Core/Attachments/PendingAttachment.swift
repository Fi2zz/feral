import Foundation
import SwiftusLLM
import UIKit

/// 发送前还在输入条里的附件，尚未落库。
enum PendingAttachment: Identifiable, Equatable {
    case image(id: UUID, data: Data, mimeType: String)
    case textFile(id: UUID, name: String, text: String)

    var id: UUID {
        switch self {
        case .image(let id, _, _): id
        case .textFile(let id, _, _): id
        }
    }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    var fileName: String {
        switch self {
        case .image: "图片"
        case .textFile(_, let name, _): name
        }
    }

    var byteCount: Int {
        switch self {
        case .image(_, let data, _): data.count
        case .textFile(_, _, let text): text.utf8.count
        }
    }

    var text: String? {
        guard case .textFile(_, _, let text) = self else { return nil }
        return text
    }

    var image: UIImage? {
        guard case .image(_, let data, _) = self else { return nil }
        return UIImage(data: data)
    }

    var llmImage: LlmImage? {
        guard case .image(_, let data, let mimeType) = self else { return nil }
        return LlmImage(mimeType: mimeType, base64Data: data.base64EncodedString())
    }

    /// 拼进 user message 的文本块。
    var promptBlock: String? {
        guard case .textFile(_, let name, let text) = self else { return nil }
        return "<file name=\"\(name)\">\n\(text)\n</file>"
    }

    static func image(data: Data, mimeType: String = "image/jpeg") -> PendingAttachment {
        .image(id: UUID(), data: data, mimeType: mimeType)
    }

    static func textFile(name: String, text: String) -> PendingAttachment {
        .textFile(id: UUID(), name: name, text: text)
    }
}
