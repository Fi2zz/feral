import Foundation
import SwiftusCore

/// Parallel MCP：`web_search` + `web_fetch`。参数与 Exa 不同，单独适配。
struct ParallelSearchProvider: Sendable {
    static let endpoint = URL(string: "https://search.parallel.ai/mcp")!
    private let client: McpClient

    init(apiKey: String?, session: URLSession = .shared) {
        var headers: [String: String] = [:]
        if let apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        client = McpClient(endpoint: Self.endpoint, headers: headers, session: session)
    }

    func search(_ query: String, limit: Int = 5, sessionID: UUID) async throws -> [SearchHit] {
        let result = try await client.callTool(
            name: "web_search",
            arguments: .object([
                "objective": .string(query),
                "search_queries": .array([.string(query)]),
                "session_id": .string(sessionID.uuidString),
            ])
        )
        let hits = ParallelSearchParser.hits(from: result.structured)
        if !hits.isEmpty { return Array(hits.prefix(limit)) }
        return Array(ParallelSearchParser.hits(fromText: result.text ?? "").prefix(limit))
    }

    func fetch(_ urls: [String], maxCharacters: Int = 3000) async throws -> [FetchedPage] {
        guard !urls.isEmpty else { return [] }
        let result = try await client.callTool(
            name: "web_fetch",
            arguments: .object(["urls": .array(urls.map { .string($0) })])
        )
        let pages = ParallelSearchParser.pages(from: result.structured, requested: urls)
        let fallback = pages.isEmpty
            ? ParallelSearchParser.pages(fromText: result.text ?? "", requested: urls)
            : pages
        return fallback.map { page in
            FetchedPage(url: page.url, text: String(page.text.prefix(maxCharacters)))
        }
    }
}
