import Foundation
import Testing

@testable import Feral

@Suite("markdown 分块")
struct MarkdownParserTests {
    @Test("纯段落")
    func paragraphs() {
        #expect(MarkdownParser.parse("先给结论，再补充细节。") == [.paragraph("先给结论，再补充细节。")])
    }

    @Test("空行切段，不把两段粘一起")
    func blankLineSplitsParagraphs() {
        let blocks = MarkdownParser.parse("第一段\n\n第二段")

        #expect(blocks == [.paragraph("第一段"), .paragraph("第二段")])
    }

    @Test("段内换行原样保留")
    func softWrapKeptInsideParagraph() {
        #expect(MarkdownParser.parse("第一行\n第二行") == [.paragraph("第一行\n第二行")])
    }

    @Test("无序列表三种符号都认，连续项归一组")
    func bullets() {
        let blocks = MarkdownParser.parse("- 方案甲\n* 方案乙\n+ 方案丙")

        #expect(blocks == [.bullets(["方案甲", "方案乙", "方案丙"])])
    }

    @Test("有序列表 1. 与 1) 都认")
    func orderedList() {
        let blocks = MarkdownParser.parse("1. 先看目标\n2) 再看约束")

        #expect(blocks == [.ordered(["先看目标", "再看约束"])])
    }

    @Test("列表后面接段落，列表要收尾")
    func listThenParagraph() {
        let blocks = MarkdownParser.parse("- 一条\n\n结论如上。")

        #expect(blocks == [.bullets(["一条"]), .paragraph("结论如上。")])
    }

    @Test("无序与有序之间互相切换会分块")
    func listTypeSwitch() {
        let blocks = MarkdownParser.parse("- 甲\n1. 乙")

        #expect(blocks == [.bullets(["甲"]), .ordered(["乙"])])
    }

    @Test("标题按井号数定级")
    func headings() {
        let blocks = MarkdownParser.parse("# 结论\n再展开一点。")

        #expect(blocks == [.heading(level: 1, text: "结论"), .paragraph("再展开一点。")])
    }

    @Test("六个以上的井号不算标题")
    func tooManyHashesIsNotHeading() {
        #expect(MarkdownParser.parse("####### 七个") == [.paragraph("####### 七个")])
    }

    @Test("没有空格的井号不是标题")
    func hashWithoutSpaceIsNotHeading() {
        #expect(MarkdownParser.parse("#标签") == [.paragraph("#标签")])
    }

    @Test("围栏代码块带语言标记")
    func fencedCodeWithLanguage() {
        let blocks = MarkdownParser.parse("看这段：\n```swift\nlet a = 1\n```\n就这样。")

        #expect(blocks == [
            .paragraph("看这段："),
            .code(language: "swift", lines: ["let a = 1"]),
            .paragraph("就这样。"),
        ])
    }

    @Test("代码块里的井号和短横线不当成标题或列表")
    func codeContentIsOpaque() {
        let blocks = MarkdownParser.parse("```\n# 这里是注释\n- 不是列表\n```")

        #expect(blocks == [.code(language: "", lines: ["# 这里是注释", "- 不是列表"])])
    }

    @Test("代码块没闭合也不吞内容")
    func unclosedCodeBlock() {
        let blocks = MarkdownParser.parse("```\nlet a = 1")

        #expect(blocks == [.code(language: "", lines: ["let a = 1"])])
    }

    @Test("空输入什么都不出")
    func emptyInput() {
        #expect(MarkdownParser.parse("") == [])
        #expect(MarkdownParser.parse("\n\n") == [])
    }

    @Test("典型回复整段分块")
    func realisticAnswer() {
        let text = """
        结论：先按第二版推进。

        原因有两条：
        - 第一版范围太大
        - 时间只剩两周

        下周按 `v2` 再来。
        """
        let blocks = MarkdownParser.parse(text)

        #expect(blocks == [
            .paragraph("结论：先按第二版推进。"),
            .paragraph("原因有两条："),
            .bullets(["第一版范围太大", "时间只剩两周"]),
            .paragraph("下周按 `v2` 再来。"),
        ])
    }
}
