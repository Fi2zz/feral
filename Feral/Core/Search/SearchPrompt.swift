import Foundation

/// 把搜索命中和抓回来的正文包成给模型看的外部数据块。
enum SearchPrompt {
    static func resultsBlock(_ hits: [SearchHit]) -> String {
        let items = hits.enumerated().map { index, hit in
            var lines = ["[\(index + 1)] \(hit.title)"]
            if !hit.url.isEmpty { lines.append("URL: \(hit.url)") }
            if !hit.snippet.isEmpty { lines.append(hit.snippet) }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return "<search_results>\n\(items)\n</search_results>"
    }

    static func pagesBlock(_ pages: [FetchedPage]) -> String {
        let items = pages.map { page in
            "<page url=\"\(page.url)\">\n\(page.text)\n</page>"
        }.joined(separator: "\n\n")
        return "<page_contents>\n\(items)\n</page_contents>"
    }
}
