import Foundation
import SwiftusSearch

/// 把搜索结果的「标题 + URL + 摘要」包成给模型看的外部数据块。
enum SearchPrompt {
    static func resultsBlock(_ results: [SearchResult]) -> String {
        let items = results.enumerated().map { index, result in
            var lines = ["[\(index + 1)] \(result.title)", "URL: \(result.url)"]
            if !result.snippet.isEmpty {
                lines.append(result.snippet)
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return "<search_results>\n\(items)\n</search_results>"
    }
}
