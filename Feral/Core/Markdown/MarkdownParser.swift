import Foundation

/// 一段回复的结构单元。
///
/// 只认对话里真会出现的几种：段落、标题、无序/有序列表、围栏代码块。
/// 表格、引用、脚注不做——日常对话用不上，做了也没人验。
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullets([String])
    case ordered([String])
    case code(language: String, lines: [String])

    /// 段落里的原文，界面拿它去解析行内格式（粗体、行内代码、链接）。
    var plainText: String {
        switch self {
        case .paragraph(let text), .heading(_, let text):
            return text
        case .bullets(let items), .ordered(let items):
            return items.joined(separator: "\n")
        case .code(_, let lines):
            return lines.joined(separator: "\n")
        }
    }
}

/// 极小的 markdown 分块器：逐行扫，按前缀归块。行内格式留给界面用
/// `AttributedString(markdown:)` 处理，这里只负责结构。
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var builder = Builder()
        for line in text.components(separatedBy: .newlines) {
            builder.consume(line)
        }
        return builder.finish()
    }

    /// 逐行累积。每种前缀一个判断函数，命中就收下这行。
    private struct Builder {
        private var blocks: [MarkdownBlock] = []
        private var paragraph: [String] = []
        private var bullets: [String] = []
        private var ordered: [String] = []
        private var code: [String] = []
        private var codeLanguage = ""
        private var inCode = false

        mutating func consume(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if consumeCodeFence(trimmed) { return }
            if inCode {
                code.append(line)
                return
            }
            if trimmed.isEmpty {
                flushAll()
                return
            }
            if consumeHeading(trimmed) { return }
            if consumeItem(trimmed) { return }
            paragraph.append(line)
        }

        /// 收尾。代码块没闭合也按已收内容吐出来，别把内容吞了。
        mutating func finish() -> [MarkdownBlock] {
            if inCode, !code.isEmpty {
                blocks.append(.code(language: codeLanguage, lines: code))
                code = []
                inCode = false
            }
            flushAll()
            return blocks
        }

        // MARK: - 各类前缀

        private mutating func consumeCodeFence(_ trimmed: String) -> Bool {
            guard trimmed.hasPrefix("```") else { return false }
            if inCode {
                blocks.append(.code(language: codeLanguage, lines: code))
                code = []
                codeLanguage = ""
                inCode = false
            } else {
                flushAll()
                inCode = true
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
            return true
        }

        private mutating func consumeHeading(_ trimmed: String) -> Bool {
            let hashes = trimmed.prefix { $0 == "#" }
            guard !hashes.isEmpty, hashes.count <= 6 else { return false }
            let rest = trimmed.dropFirst(hashes.count)
            guard rest.hasPrefix(" ") else { return false }
            flushAll()
            blocks.append(.heading(
                level: hashes.count,
                text: rest.trimmingCharacters(in: .whitespaces)
            ))
            return true
        }

        private mutating func consumeItem(_ trimmed: String) -> Bool {
            if let item = Self.bulletItem(trimmed) {
                flushParagraph()
                flushOrdered()
                bullets.append(item)
                return true
            }
            if let item = Self.orderedItem(trimmed) {
                flushParagraph()
                flushBullets()
                ordered.append(item)
                return true
            }
            return false
        }

        private static func bulletItem(_ line: String) -> String? {
            for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }

        /// `1. ` / `12) ` 两种写法都认。
        private static func orderedItem(_ line: String) -> String? {
            let digits = line.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 2 else { return nil }
            let rest = line.dropFirst(digits.count)
            for marker in [". ", ") "] where rest.hasPrefix(marker) {
                return String(rest.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }

        // MARK: - 收尾

        private mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        /// 换列表类型时把「另一种」收尾成块——直接清空会把前一组吞掉。
        private mutating func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bullets(bullets))
            bullets = []
        }

        private mutating func flushOrdered() {
            guard !ordered.isEmpty else { return }
            blocks.append(.ordered(ordered))
            ordered = []
        }

        private mutating func flushAll() {
            flushParagraph()
            flushBullets()
            flushOrdered()
        }
    }
}
