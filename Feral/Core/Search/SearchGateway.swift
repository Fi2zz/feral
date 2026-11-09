import Foundation

/// 搜索网关：Exa 优先，空结果或失败时回退 Parallel；搜索后抓前两条正文。
struct SearchGateway {
    let exaKey: String?
    let parallelKey: String?
    let session: URLSession
    let fetchCount: Int
    let maxCharacters: Int

    init(
        exaKey: String?,
        parallelKey: String?,
        session: URLSession = .shared,
        fetchCount: Int = 2,
        maxCharacters: Int = 3000
    ) {
        self.exaKey = exaKey
        self.parallelKey = parallelKey
        self.session = session
        self.fetchCount = fetchCount
        self.maxCharacters = maxCharacters
    }

    func search(_ query: String, limit: Int = 5, sessionID: UUID) async throws -> SearchBundle {
        var errors: [String] = []

        if let bundle = await exa(query, limit: limit), !bundle.hits.isEmpty {
            return bundle
        } else {
            errors.append("Exa：没有结果或请求失败")
        }

        do {
            return try await parallel(query, limit: limit, sessionID: sessionID)
        } catch {
            errors.append("Parallel：\(error.localizedDescription)")
        }

        throw SearchGatewayError.allFailed(errors)
    }

    private func exa(_ query: String, limit: Int) async -> SearchBundle? {
        do {
            let provider = ExaSearchProvider(apiKey: exaKey, session: session)
            let hits = try await provider.search(query, limit: limit)
            guard !hits.isEmpty else { return nil }
            let urls = hits.prefix(fetchCount).map(\.url).filter { !$0.isEmpty }
            let pages = urls.isEmpty
                ? []
                : ((try? await provider.fetch(Array(urls), maxCharacters: maxCharacters)) ?? [])
            return SearchBundle(hits: hits, pages: pages)
        } catch {
            return nil
        }
    }

    private func parallel(_ query: String, limit: Int, sessionID: UUID) async throws -> SearchBundle {
        let provider = ParallelSearchProvider(apiKey: parallelKey, session: session)
        let hits = try await provider.search(query, limit: limit, sessionID: sessionID)
        let urls = hits.prefix(fetchCount).map(\.url).filter { !$0.isEmpty }
        let pages = urls.isEmpty
            ? []
            : ((try? await provider.fetch(Array(urls), maxCharacters: maxCharacters)) ?? [])
        return SearchBundle(hits: hits, pages: pages)
    }
}

enum SearchGatewayError: LocalizedError {
    case allFailed([String])

    var errorDescription: String? {
        switch self {
        case .allFailed(let reasons):
            "所有搜索源都失败了：（\(reasons.joined(separator: "；"))）"
        }
    }
}
