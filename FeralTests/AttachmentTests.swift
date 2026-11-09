import Foundation
import Testing
import UIKit

@testable import Feral

@Suite("文本文件读取")
struct TextFileLoaderTests {
    @Test("UTF-8 正常解码")
    func utf8() {
        #expect(TextFileLoader.decode(Data("你好，世界".utf8)) == "你好，世界")
    }

    @Test("UTF-16 BOM 解码")
    func utf16() throws {
        var data = Data([0xFF, 0xFE])
        data.append(try #require("你好".data(using: .utf16LittleEndian)))
        #expect(TextFileLoader.decode(data) == "你好")
    }

    @Test("超长文本按字符数截断并标注")
    func truncate() {
        let text = String(repeating: "字", count: 10)
        let cut = TextFileLoader.truncate(text, to: 4)

        #expect(cut.hasPrefix("字字字字"))
        #expect(cut.contains("已截断"))
    }

    @Test("从临时文件读取")
    func loadFromFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("feral-text-\(UUID().uuidString).md")
        try Data("# 标题\n正文".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let attachment = try TextFileLoader.load(url: url)
        guard case .textFile(_, let name, let text) = attachment else {
            Issue.record("应当读成文本附件")
            return
        }
        #expect(name.hasSuffix(".md"))
        #expect(text.contains("# 标题"))
    }
}

@Suite("图片读取")
struct ImageLoaderTests {
    @Test("长边压到 2048 以内并转成 JPEG")
    func downscale() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let source = try #require(image.pngData())

        let attachment = try ImageLoader.load(data: source)
        guard case .image(_, let jpeg, let mimeType) = attachment else {
            Issue.record("应当读成图片附件")
            return
        }
        let decoded = try #require(UIImage(data: jpeg))
        #expect(mimeType == "image/jpeg")
        #expect(max(decoded.size.width, decoded.size.height) <= ImageLoader.maxDimension)
        #expect(attachment.llmImage?.base64Data.isEmpty == false)
    }
}

@MainActor
@Suite("附件 prompt")
struct AttachmentPromptTests {
    @Test("文本附件拼进 user 消息")
    func textFileBlock() {
        let prompt = ChatStore.prompt(
            for: "总结一下",
            attachments: [.textFile(name: "a.md", text: "# hi")]
        )

        #expect(prompt.contains("总结一下"))
        #expect(prompt.contains("<file name=\"a.md\">"))
        #expect(prompt.contains("# hi"))
    }

    @Test("只有图片时给默认问题")
    func imagesOnly() {
        let prompt = ChatStore.prompt(
            for: "",
            attachments: [.image(data: Data([1]), mimeType: "image/jpeg")]
        )

        #expect(prompt == "请描述图片内容。")
    }

    @Test("搜索结果包成 <search_results> 并附链接")
    func searchResultsBlock() {
        let block = SearchPrompt.resultsBlock([
            SearchHit(title: "标题", url: "https://example.com", snippet: "摘要"),
        ])

        #expect(block.contains("<search_results>"))
        #expect(block.contains("https://example.com"))
        #expect(block.contains("摘要"))
    }

    @Test("附件与搜索结果同时进 prompt")
    func attachmentsAndSearch() {
        let prompt = ChatStore.prompt(
            for: "总结一下",
            attachments: [.textFile(name: "a.md", text: "# hi")],
            searchResults: [SearchHit(title: "标题", url: "https://example.com", snippet: "摘要")]
        )

        #expect(prompt.contains("<file name=\"a.md\">"))
        #expect(prompt.contains("<search_results>"))
    }

    @Test("带搜索结果的 system prompt 说明外部数据与引用")
    func searchSystemInstruction() {
        let system = ChatPrompt.system(includesSearchResults: true)

        #expect(system.contains("<search_results>"))
        #expect(system.contains("来源链接"))
    }
}

@Suite("搜索开关")
struct SearchSettingsTests {
    @Test("默认关闭，保存后记得住")
    func persists() throws {
        let defaults = try #require(UserDefaults(suiteName: "search-settings-\(UUID().uuidString)"))
        #expect(SearchSettings.enabled(in: defaults) == false)

        SearchSettings.save(enabled: true, to: defaults)
        #expect(SearchSettings.enabled(in: defaults))
    }
}

@MainActor
@Suite("附件落库", .serialized)
struct AttachmentPersistenceTests {
    @Test("文本附件随用户消息落库")
    func textAttachmentPersists() async throws {
        let defaults = try #require(UserDefaults(suiteName: "attachment-\(UUID().uuidString)"))
        KimiConversationStore.startNew(in: defaults)
        let store = ChatStore(
            modelContext: try TestStore.freshContext(),
            runtime: RuntimeStore(),
            defaults: defaults
        )

        await store.send("看看这个", attachments: [.textFile(name: "note.txt", text: "hello")])

        let message = try #require(store.messages.first)
        #expect(message.attachments.count == 1)
        #expect(message.attachments.first?.fileName == "note.txt")
        #expect(message.attachments.first?.text == "hello")
    }
}
