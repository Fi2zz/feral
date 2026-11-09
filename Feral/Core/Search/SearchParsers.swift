import Foundation
import SwiftusCore

/// Exa 返回的文本块：搜索结果 `Title/URL/Highlights`，抓正文 `URL` 分段。
enum ExaSearchParser {
    static func hits(from text: String) -> [SearchHit] {
        let blocks = text.components(separatedBy: "\n\n---\n\n")
        let hits = blocks.compactMap { block -> SearchHit? in
            guard let url = field("URL", in: block) else { return nil }
            let title = field("Title", in: block) ?? url
            let snippet = section("Highlights", in: block) ?? section("Text", in: block) ?? ""
            return SearchHit(
                title: title,
                url: url,
                snippet: snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        if !hits.isEmpty { return hits }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [SearchHit(title: "搜索结果", url: "", snippet: trimmed)]
    }

    static func pages(from text: String, requested: [String]) -> [FetchedPage] {
        let blocks = text.components(separatedBy: "\n\n---\n\n")
        return blocks.compactMap { block -> FetchedPage? in
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let url = field("URL", in: block) ?? requested.first ?? ""
            return FetchedPage(url: url, text: trimmed)
        }
    }

    private static func field(_ key: String, in block: String) -> String? {
        for line in block.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }
            let value = trimmed.dropFirst(key.count + 1)
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty, value != "N/A" { return value }
        }
        return nil
    }

    private static func section(_ key: String, in block: String) -> String? {
        guard let range = block.range(of: "\(key):") else { return nil }
        let value = block[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// Parallel 返回 `structuredContent.results`；没有结构化内容时回退解析 text 里的 JSON。
enum ParallelSearchParser {
    static func hits(from value: JSONValue?) -> [SearchHit] {
        guard let results = value?["results"]?.arrayValue else { return [] }
        return results.compactMap { item in
            guard let url = item["url"]?.stringValue else { return nil }
            let title = item["title"]?.stringValue ?? url
            let excerpts = item["excerpts"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return SearchHit(title: title, url: url, snippet: excerpts.joined(separator: "\n\n"))
        }
    }

    static func hits(fromText text: String) -> [SearchHit] {
        guard let data = text.data(using: .utf8),
              let value = try? JSONValue.parse(data) else { return [] }
        return hits(from: value)
    }

    static func pages(from value: JSONValue?, requested: [String]) -> [FetchedPage] {
        guard let results = value?["results"]?.arrayValue else { return [] }
        return results.compactMap { item in
            let url = item["url"]?.stringValue ?? requested.first ?? ""
            guard !url.isEmpty else { return nil }
            let full = item["full_content"]?.stringValue
            let excerpts = item["excerpts"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let text = (full?.isEmpty == false ? full : excerpts.joined(separator: "\n\n")) ?? ""
            return text.isEmpty ? nil : FetchedPage(url: url, text: text)
        }
    }

    static func pages(fromText text: String, requested: [String]) -> [FetchedPage] {
        guard let data = text.data(using: .utf8),
              let value = try? JSONValue.parse(data) else { return [] }
        return pages(from: value, requested: requested)
    }
}
