import Foundation

/// 一条搜索结果。url 为空表示服务器只回了一段纯文本。
struct SearchHit: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var url: String
    var snippet: String

    init(id: UUID = UUID(), title: String, url: String, snippet: String = "") {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

/// 抓回来的网页正文。
struct FetchedPage: Equatable, Sendable {
    var url: String
    var text: String
}

/// 一次「搜索 + 抓正文」的结果。
struct SearchBundle: Equatable, Sendable {
    var hits: [SearchHit]
    var pages: [FetchedPage]

    static let empty = SearchBundle(hits: [], pages: [])

    var isEmpty: Bool { hits.isEmpty && pages.isEmpty }
}
