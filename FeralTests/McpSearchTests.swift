import Foundation
import Testing

@testable import Feral

final class MockMcpURLProtocol: URLProtocol {
    struct Captured {
        let request: URLRequest
        let body: Data?
    }

    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var captured: [Captured] = []

    static var requests: [Captured] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    static func setHandler(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        captured = []
        self.handler = handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            let (response, data) = try handler!(request)
            Self.lock.lock()
            Self.captured.append(Captured(request: request, body: Self.readBody(of: request)))
            Self.lock.unlock()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(contentsOf: buffer[..<read])
        }
        return data
    }
}

private func mockMCPSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockMcpURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func httpOK() -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://mock.local")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

private let exaSearchText = """
Title: First
URL: https://a.example
Published: N/A
Highlights:
First snippet

---

Title: Second
URL: https://b.example
Highlights:
Second snippet
"""

@MainActor
@Suite("MCP 搜索", .serialized)
struct McpSearchTests {
    @Test("MCP SSE 响应只取 result.content 的第一段文本")
    func sseResult() throws {
        let payload = try jsonData([
            "jsonrpc": "2.0",
            "id": 1,
            "result": ["content": [["type": "text", "text": "hello"]]],
        ])
        let sse = Data("event: message\ndata: ".utf8) + payload + Data("\n\n".utf8)

        #expect(try McpParser.result(from: sse).text == "hello")
    }

    @Test("Exa provider 发 web_search_exa，并解析 SSE 里的结果")
    func exaProvider() async throws {
        MockMcpURLProtocol.setHandler { _ in
            let payload = try jsonData([
                "jsonrpc": "2.0",
                "id": 1,
                "result": ["content": [["type": "text", "text": exaSearchText]]],
            ])
            let body = Data("event: message\ndata: ".utf8) + payload + Data("\n\n".utf8)
            return (httpOK(), body)
        }
        let provider = ExaSearchProvider(apiKey: "exa-key", session: mockMCPSession())

        let hits = try await provider.search("swift", limit: 2)

        #expect(hits.count == 2)
        #expect(hits.first?.title == "First")
        #expect(hits.last?.url == "https://b.example")
        let captured = try #require(MockMcpURLProtocol.requests.first)
        #expect(captured.request.url?.query?.contains("exaApiKey=exa-key") == true)
        let body = try #require(captured.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let params = try #require(object["params"] as? [String: Any])
        #expect(params["name"] as? String == "web_search_exa")
    }

    @Test("Parallel provider 发 web_search，并按 structuredContent 解析")
    func parallelProvider() async throws {
        MockMcpURLProtocol.setHandler { _ in
            let payload = try jsonData([
                "jsonrpc": "2.0",
                "id": 1,
                "result": [
                    "content": [["type": "text", "text": "ok"]],
                    "structuredContent": [
                        "results": [[
                            "url": "https://p.example",
                            "title": "P",
                            "excerpts": ["excerpt"],
                        ]],
                    ],
                ],
            ])
            return (httpOK(), payload)
        }
        let provider = ParallelSearchProvider(apiKey: "parallel-key", session: mockMCPSession())
        let sessionID = UUID()

        let hits = try await provider.search("swift", limit: 5, sessionID: sessionID)

        #expect(hits.first?.url == "https://p.example")
        let captured = try #require(MockMcpURLProtocol.requests.first)
        #expect(captured.request.value(forHTTPHeaderField: "Authorization") == "Bearer parallel-key")
        let body = try #require(captured.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let params = try #require(object["params"] as? [String: Any])
        let arguments = try #require(params["arguments"] as? [String: Any])
        #expect(params["name"] as? String == "web_search")
        #expect(arguments["session_id"] as? String == sessionID.uuidString)
    }

    @Test("Exa 失败时网关回退 Parallel，并抓前两条正文")
    func gatewayFallsBack() async throws {
        MockMcpURLProtocol.setHandler { request in
            guard request.url?.host == "mcp.exa.ai" else {
                let payload = try jsonData([
                    "jsonrpc": "2.0",
                    "id": 1,
                    "result": [
                        "content": [["type": "text", "text": "ok"]],
                        "structuredContent": [
                            "results": [[
                                "url": "https://p.example",
                                "title": "P",
                                "excerpts": ["page body"],
                            ]],
                        ],
                    ],
                ])
                return (httpOK(), payload)
            }
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!, Data("exa down".utf8))
        }
        let gateway = SearchGateway(exaKey: nil, parallelKey: nil, session: mockMCPSession())

        let bundle = try await gateway.search("swift", sessionID: UUID())

        #expect(bundle.hits.first?.title == "P")
        #expect(bundle.pages.first?.text == "page body")
    }
}
