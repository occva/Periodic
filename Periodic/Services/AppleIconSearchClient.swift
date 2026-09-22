import Foundation

actor AppleIconSearchClient {
    enum SearchError: LocalizedError {
        case invalidRequest
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidRequest: "无法创建 Apple 图标搜索请求。"
            case .invalidResponse: "Apple 图标服务返回了无法识别的数据。"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(term: String, country: String = "cn", limit: Int = 12) async throws -> [AppleIconSearchResult] {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 30)))
        ]
        guard let url = components?.url else { throw SearchError.invalidRequest }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw SearchError.invalidResponse
        }
        let payload = try JSONDecoder().decode(SearchResponse.self, from: data)
        return payload.results.compactMap { item in
            guard let artworkURL = item.highResolutionArtworkURL else { return nil }
            return AppleIconSearchResult(
                id: item.trackId,
                name: item.trackName,
                artistName: item.artistName,
                artworkURL: artworkURL
            )
        }
    }
}

private struct SearchResponse: Decodable {
    let results: [SearchItem]
}

private struct SearchItem: Decodable {
    let trackId: Int64
    let trackName: String
    let artistName: String
    let artworkUrl512: URL?
    let artworkUrl100: URL?

    var highResolutionArtworkURL: URL? {
        let source = artworkUrl512 ?? artworkUrl100
        guard let source else { return nil }
        let upgraded = source.absoluteString
            .replacingOccurrences(of: "/100x100bb.", with: "/512x512bb.")
        return URL(string: upgraded) ?? source
    }
}
