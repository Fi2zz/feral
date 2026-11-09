import Foundation
import SwiftusCore

/// 一次 MCP `tools/call` 的结果：文本 + 可选的结构化内容。
struct McpResult: Sendable {
    var text: String?
    var structured: JSONValue?
}

/// 极简 MCP 客户端：JSON-RPC 2.0 `tools/call`，普通 JSON 与 SSE 都认。
struct McpClient {
    static let maxResponseBytes = 256 * 1024

    let endpoint: URL
    let headers: [String: String]
    let session: URLSession
    let timeout: TimeInterval

    init(
        endpoint: URL,
        headers: [String: String] = [:],
        session: URLSession = .shared,
        timeout: TimeInterval = 25
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.session = session
        self.timeout = timeout
    }

    func callTool(name: String, arguments: JSONValue) async throws -> McpResult {
        let body = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .int(1),
            "method": .string("tools/call"),
            "params": .object([
                "name": .string(name),
                "arguments": arguments,
            ]),
        ])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try body.jsonData()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw McpError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw McpError.http(http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
        }
        guard data.count <= Self.maxResponseBytes else { throw McpError.responseTooLarge }
        return try McpParser.result(from: data)
    }
}

enum McpError: LocalizedError {
    case invalidResponse
    case http(Int, String)
    case responseTooLarge
    case rpc(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "MCP 返回了无法识别的响应。"
        case .http(let status, let body): "MCP HTTP \(status)：\(body)"
        case .responseTooLarge: "MCP 响应超过 256 KB。"
        case .rpc(let message): "MCP 错误：\(message)"
        }
    }
}

enum McpParser {
    static func result(from data: Data) throws -> McpResult {
        for payload in payloads(from: data) {
            guard let value = try? JSONValue.parse(payload) else { continue }
            if let message = value["error"]?["message"]?.stringValue {
                throw McpError.rpc(message)
            }
            guard let result = value["result"] else { continue }
            let item = result["content"]?.arrayValue?.first { $0["text"]?.stringValue != nil }
            let structured = result["structuredContent"]
            let hasStructured = structured != nil && structured != .null
            if item != nil || hasStructured {
                return McpResult(text: item?["text"]?.stringValue, structured: hasStructured ? structured : nil)
            }
        }
        throw McpError.invalidResponse
    }

    private static func payloads(from data: Data) -> [Data] {
        var payloads = [data]
        let raw = String(decoding: data, as: UTF8.self)
        for line in raw.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("data: ") else { continue }
            if let payload = String(line.dropFirst(6)).data(using: .utf8) {
                payloads.append(payload)
            }
        }
        return payloads
    }
}
