import SwiftUI

/// 把回复按块渲染：段落、标题、列表、代码块。
///
/// 行内格式（粗体、斜体、行内代码、链接）交给系统 `AttributedString(markdown:)`，
/// 它认 `**粗**`、`` `代码` ``、`[文字](url)` 这些；块级结构由 `MarkdownParser` 切好，
/// 因为 `Text` 不会渲染列表和代码块。
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(inline(text))
                .textSelection(.enabled)
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .textSelection(.enabled)
        case .bullets(let items):
            itemList(items, marker: "•")
        case .ordered(let items):
            orderedList(items)
        case .code(_, let lines):
            codeBlock(lines)
        }
    }

    private func orderedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(inline(item))
                }
            }
        }
    }

    private func itemList(_ items: [String], marker: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(marker)
                        .foregroundStyle(.secondary)
                    Text(inline(item))
                }
            }
        }
    }

    private func codeBlock(_ lines: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(lines.joined(separator: "\n"))
                .font(.system(.callout, design: .monospaced))
                .padding(10)
        }
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
    }

    /// 行内 markdown 解析失败就退回原文，不能让一条回复因为格式问题显示不出来。
    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.bold()
        case 2: .headline
        default: .subheadline.bold()
        }
    }
}
