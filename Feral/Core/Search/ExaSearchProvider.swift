import Foundation
import SwiftusCore

/// Exa MCP：`web_search_exa` + `web_fetch_exa`。
struct ExaSearchProvider: Sendable {
    static let endpoint = URL(string: "https://mcp.exa.ai/mcp")!
    private let client: McpClient

    init(apiKey: String?, session: URLSession = .shared) {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        if let apiKey, !apiKey.isEmpty {
            components.queryItems = [URLQueryItem(name: "exaApiKey", value: apiKey)]
        }
        client = McpClient(endpoint: components.url!, session: session)
    }

    func search(_ query: String, limit: Int = 5) async throws -> [SearchHit] {
        let result = try await client.callTool(
            name: "web_search_exa",
            arguments: .object([
                "query": .string(query),
                // 当前 schema 要求 objective；没有额外目标时就用问句本身。
                "objective": .string(query),
                "numResults": .int(Int64(limit)),
            ])
        )
        return ExaSearchParser.hits(from: result.text ?? "")
    }

    func fetch(_ urls: [String], maxCharacters: Int = 3000) async throws -> [FetchedPage] {
        guard !urls.isEmpty else { return [] }
        let result = try await client.callTool(
            name: "web_fetch_exa",
            arguments: .object([
                "urls": .array(urls.map { .string($0) }),
                "maxCharacters": .int(Int64(maxCharacters)),
            ])
        )
        return ExaSearchParser.pages(from: result.text ?? "", requested: urls)
    }
}
