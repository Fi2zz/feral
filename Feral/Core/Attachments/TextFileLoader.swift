import Foundation
import UniformTypeIdentifiers

/// 纯文本文件读取：大小上限、编码回退、按字符数截断。
enum TextFileLoader {
    static let maxFileBytes = 10 * 1024 * 1024
    static let maxCharsPerFile = 200_000
    static let maxTotalChars = 400_000

    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .sourceCode, .commaSeparatedText, .json, .xml, .html]
        for ext in [
            "md", "markdown", "yaml", "yml", "toml", "log",
            "swift", "kt", "js", "ts", "tsx", "jsx", "py", "go", "rs",
            "java", "c", "cpp", "h", "m", "mm", "sh", "zsh", "sql", "ini", "conf",
        ] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    enum LoadError: LocalizedError {
        case tooLarge
        case unreadable
        case unsupportedEncoding

        var errorDescription: String? {
            switch self {
            case .tooLarge: "文件超过 10 MB，换个小一点的。"
            case .unreadable: "文件读不出来。"
            case .unsupportedEncoding: "这个文件的文本编码认不出，建议转成 UTF-8。"
            }
        }
    }

    static func load(url: URL) throws -> PendingAttachment {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maxFileBytes {
            throw LoadError.tooLarge
        }
        guard let data = try? Data(contentsOf: url) else { throw LoadError.unreadable }
        guard data.count <= maxFileBytes else { throw LoadError.tooLarge }
        guard let text = decode(data) else { throw LoadError.unsupportedEncoding }

        return .textFile(name: url.lastPathComponent, text: truncate(text, to: maxCharsPerFile))
    }

    /// 按剩余预算截断，返回截断后的文本。
    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit))) + "\n\n（内容过长，已截断）"
    }

    static func decode(_ data: Data) -> String? {
        // 带 BOM 的 UTF-16 用 .utf16 解，编码器会把 BOM 吃掉，不留成正文首字符。
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        if let text = String(data: data, encoding: gb) {
            return text
        }
        return String(data: data, encoding: .isoLatin1)
    }
}
