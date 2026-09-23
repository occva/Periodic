import Foundation

actor FrankfurterExchangeRateClient {
    struct NetworkResponse: Sendable {
        let data: Data
        let statusCode: Int
    }

    typealias DataLoader = @Sendable (URL) async throws -> NetworkResponse

    enum ClientError: LocalizedError {
        case invalidRequest
        case invalidResponse
        case incompleteRates

        var errorDescription: String? {
            switch self {
            case .invalidRequest:
                "无法创建 Frankfurter 汇率请求。"
            case .invalidResponse:
                "Frankfurter 返回了无法识别的数据。"
            case .incompleteRates:
                "Frankfurter 未返回全部所需币种的汇率。"
            }
        }
    }

    private struct RatePayload: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Decimal
    }

    private struct CacheDocument: Codable {
        var entries: [String: ExchangeRateCatalog]
    }

    private static let freshnessInterval: TimeInterval = 6 * 60 * 60

    private let dataLoader: DataLoader
    private let cacheURL: URL?
    private var cache: [CurrencyCode: ExchangeRateCatalog] = [:]
    private var inFlightRefreshes: [CurrencyCode: Task<ExchangeRateCatalog, Error>] = [:]
    private var didLoadCache = false

    init() {
        dataLoader = Self.loadFromNetwork
        cacheURL = Self.defaultCacheURL
    }

    init(cacheURL: URL?, dataLoader: @escaping DataLoader) {
        self.dataLoader = dataLoader
        self.cacheURL = cacheURL
    }

    func latestQuote(
        baseCurrency: CurrencyCode,
        currencies: Set<CurrencyCode>,
        now: Date = .now
    ) async throws -> ExchangeRateQuote {
        let catalog = try await latestCatalog(baseCurrency: baseCurrency, now: now)
        var rates: [CurrencyCode: Decimal] = [:]
        for currency in currencies.union([baseCurrency]) {
            guard let rate = catalog.ratesPerBaseUnit[currency.rawValue] else {
                throw ClientError.incompleteRates
            }
            rates[currency] = rate
        }
        return ExchangeRateQuote(
            baseCurrency: catalog.baseCurrency,
            date: catalog.dateDescription(for: currencies.map(\.rawValue)),
            ratesPerBaseUnit: rates,
            isStale: catalog.isStale,
            source: .frankfurter
        )
    }

    func cachedCatalog(baseCurrency: CurrencyCode, now: Date = .now) -> ExchangeRateCatalog? {
        loadCacheIfNeeded()
        guard let cached = cache[baseCurrency] else { return nil }
        return cached.withStaleStatus(
            now.timeIntervalSince(cached.fetchedAt) >= Self.freshnessInterval
        )
    }

    func latestCatalog(
        baseCurrency: CurrencyCode,
        now: Date = .now
    ) async throws -> ExchangeRateCatalog {
        if let cached = cachedCatalog(baseCurrency: baseCurrency, now: now), !cached.isStale {
            return cached
        }

        do {
            return try await refreshCatalog(baseCurrency: baseCurrency, now: now)
        } catch {
            guard let cached = cache[baseCurrency] else { throw error }
            return cached.withStaleStatus(true)
        }
    }

    func refreshCatalog(
        baseCurrency: CurrencyCode,
        now: Date = .now
    ) async throws -> ExchangeRateCatalog {
        if let inFlight = inFlightRefreshes[baseCurrency] {
            return try await inFlight.value
        }

        let refresh = Task {
            try await fetchCatalog(baseCurrency: baseCurrency, fetchedAt: now)
        }
        inFlightRefreshes[baseCurrency] = refresh
        defer { inFlightRefreshes[baseCurrency] = nil }

        let catalog = try await refresh.value
        var updatedCache = cache
        updatedCache[baseCurrency] = catalog
        try saveCache(updatedCache)
        cache = updatedCache
        return catalog
    }

    private func fetchCatalog(
        baseCurrency: CurrencyCode,
        fetchedAt: Date
    ) async throws -> ExchangeRateCatalog {
        var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")
        components?.queryItems = [
            URLQueryItem(name: "base", value: baseCurrency.rawValue),
        ]
        guard let url = components?.url else { throw ClientError.invalidRequest }

        let response = try await dataLoader(url)
        guard (200..<300).contains(response.statusCode) else {
            throw ClientError.invalidResponse
        }
        let payloads: [RatePayload]
        do {
            payloads = try JSONDecoder().decode([RatePayload].self, from: response.data)
        } catch {
            throw ClientError.invalidResponse
        }
        let quoteCodes = payloads.map(\.quote)
        guard !payloads.isEmpty,
              payloads.allSatisfy({ $0.base == baseCurrency.rawValue && $0.rate > 0 }),
              Set(quoteCodes).count == quoteCodes.count else {
            throw ClientError.incompleteRates
        }

        var rates = Dictionary(uniqueKeysWithValues: payloads.map { ($0.quote, $0.rate) })
        var dates = Dictionary(uniqueKeysWithValues: payloads.map { ($0.quote, $0.date) })
        rates[baseCurrency.rawValue] = 1
        dates[baseCurrency.rawValue] = dates[baseCurrency.rawValue] ?? payloads.map(\.date).max()
        guard rates[baseCurrency.rawValue] != nil else {
            throw ClientError.incompleteRates
        }
        return ExchangeRateCatalog(
            baseCurrency: baseCurrency,
            fetchedAt: fetchedAt,
            ratesPerBaseUnit: rates,
            datesByCurrency: dates,
            isStale: false
        )
    }

    private func loadCacheIfNeeded() {
        guard !didLoadCache else { return }
        didLoadCache = true
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let document = try? JSONDecoder().decode(CacheDocument.self, from: data) else {
            return
        }
        cache = document.entries.reduce(into: [:]) { result, item in
            guard let currency = CurrencyCode(rawValue: item.key) else { return }
            result[currency] = item.value
        }
    }

    private func saveCache(_ entries: [CurrencyCode: ExchangeRateCatalog]) throws {
        guard let cacheURL else { return }
        let document = CacheDocument(
            entries: Dictionary(uniqueKeysWithValues: entries.map { ($0.key.rawValue, $0.value) })
        )
        let data = try JSONEncoder().encode(document)
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: cacheURL, options: .atomic)
    }

    private static var defaultCacheURL: URL {
        URL.cachesDirectory
            .appending(path: "Periodic", directoryHint: .isDirectory)
            .appending(path: "frankfurter-rates.json")
    }

    private static func loadFromNetwork(_ url: URL) async throws -> NetworkResponse {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            return NetworkResponse(data: data, statusCode: 0)
        }
        return NetworkResponse(data: data, statusCode: http.statusCode)
    }
}
