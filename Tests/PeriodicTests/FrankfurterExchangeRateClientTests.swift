import Foundation
import Testing
@testable import Periodic

struct FrankfurterExchangeRateClientTests {
    @Test func catalogRowsSearchCodeAndLocalizedName() {
        let catalog = ExchangeRateCatalog(
            baseCurrency: .cny,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
            ratesPerBaseUnit: ["CNY": 1, "USD": Decimal(14) / Decimal(100)],
            datesByCurrency: ["CNY": "2026-09-23", "USD": "2026-09-22"],
            isStale: false
        )

        #expect(catalog.rows.map(\.currencyCode) == ["CNY", "USD"])
        #expect(catalog.rows.filter { $0.matches("usd") }.map(\.currencyCode) == ["USD"])
        #expect(catalog.rows.allSatisfy { $0.matches("") })
        #expect(catalog.dateDescription(for: ["CNY", "USD"]) == "2026-09-22–2026-09-23")
    }

    @Test func latestQuoteDecodesRatesAndUsesFreshMemoryCache() async throws {
        let loader = RateLoader(replies: [.success(Self.validResponse)])
        let client = FrankfurterExchangeRateClient(
            cacheURL: nil,
            dataLoader: { url in try await loader.load(url) }
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try await client.latestQuote(
            baseCurrency: .cny,
            currencies: Set(CurrencyCode.allCases),
            now: now
        )
        let second = try await client.latestQuote(
            baseCurrency: .cny,
            currencies: Set(CurrencyCode.allCases),
            now: now.addingTimeInterval(60)
        )

        #expect(first == second)
        #expect(first.baseCurrency == .cny)
        #expect(first.date == "2026-09-22–2026-09-23")
        #expect(first.ratesPerBaseUnit[.cny] == 1)
        #expect(first.ratesPerBaseUnit[.usd] == Decimal(string: "0.1403"))
        #expect(first.source == .frankfurter)
        #expect(first.isStale == false)
        #expect(await loader.callCount == 1)

        let requestedURL = try #require(await loader.requestedURLs.first)
        let components = try #require(URLComponents(url: requestedURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v2/rates")
        #expect(components.queryItems?.first(where: { $0.name == "base" })?.value == "CNY")
        #expect(components.queryItems?.contains(where: { $0.name == "quotes" }) == false)

        let catalog = try await client.latestCatalog(baseCurrency: .cny, now: now)
        #expect(catalog.ratesPerBaseUnit["EUR"] == Decimal(string: "0.1288"))
        #expect(catalog.rows.count == 5)
    }

    @Test func concurrentCatalogLoadsShareOneNetworkRefresh() async throws {
        let loader = RateLoader(replies: [.success(Self.validResponse)])
        let client = FrankfurterExchangeRateClient(
            cacheURL: nil,
            dataLoader: { url in
                let response = try await loader.load(url)
                try await Task.sleep(for: .milliseconds(50))
                return response
            }
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try await withThrowingTaskGroup(of: ExchangeRateCatalog.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await client.latestCatalog(baseCurrency: .cny, now: now)
                }
            }
            for try await catalog in group {
                #expect(catalog.baseCurrency == .cny)
            }
        }

        #expect(await loader.callCount == 1)
    }

    @Test func staleCacheIsReturnedWhenRefreshFails() async throws {
        let loader = RateLoader(replies: [.success(Self.validResponse), .failure])
        let client = FrankfurterExchangeRateClient(
            cacheURL: nil,
            dataLoader: { url in try await loader.load(url) }
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await client.latestQuote(
            baseCurrency: .cny,
            currencies: Set(CurrencyCode.allCases),
            now: now
        )

        let stale = try await client.latestQuote(
            baseCurrency: .cny,
            currencies: Set(CurrencyCode.allCases),
            now: now.addingTimeInterval(7 * 60 * 60)
        )

        #expect(stale.isStale)
        #expect(stale.source == .frankfurter)
        #expect(stale.date == "2026-09-22–2026-09-23")
        #expect(await loader.callCount == 2)
    }

    @Test func completeCatalogPersistsAndLoadsWithoutNetwork() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appending(path: "periodic-rates-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let writerLoader = RateLoader(replies: [.success(Self.validResponse)])
        let writer = FrankfurterExchangeRateClient(
            cacheURL: cacheURL,
            dataLoader: { url in try await writerLoader.load(url) }
        )
        _ = try await writer.refreshCatalog(baseCurrency: .cny, now: now)

        let readerLoader = RateLoader(replies: [.failure])
        let reader = FrankfurterExchangeRateClient(
            cacheURL: cacheURL,
            dataLoader: { url in try await readerLoader.load(url) }
        )
        let restored = try await reader.latestCatalog(
            baseCurrency: .cny,
            now: now.addingTimeInterval(60)
        )

        #expect(restored.rows.count == 5)
        #expect(restored.ratesPerBaseUnit["EUR"] == Decimal(string: "0.1288"))
        #expect(await readerLoader.callCount == 0)
    }

    @Test func incompleteResponseIsRejected() async {
        let response = FrankfurterExchangeRateClient.NetworkResponse(
            data: Data("""
            [{"date":"2026-09-23","base":"CNY","quote":"USD","rate":0.1403}]
            """.utf8),
            statusCode: 200
        )
        let loader = RateLoader(replies: [.success(response)])
        let client = FrankfurterExchangeRateClient(
            cacheURL: nil,
            dataLoader: { url in try await loader.load(url) }
        )

        do {
            _ = try await client.latestQuote(
                baseCurrency: .cny,
                currencies: Set(CurrencyCode.allCases)
            )
            Issue.record("缺少所需币种时不应返回部分汇率。")
        } catch let error as FrankfurterExchangeRateClient.ClientError {
            guard case .incompleteRates = error else {
                Issue.record("应返回 incompleteRates，实际为 \(error)。")
                return
            }
        } catch {
            Issue.record("应返回客户端领域错误，实际为 \(error)。")
        }
    }

    @Test func networkFailureWithoutCacheIsPropagated() async {
        let loader = RateLoader(replies: [.failure])
        let client = FrankfurterExchangeRateClient(
            cacheURL: nil,
            dataLoader: { url in try await loader.load(url) }
        )

        await #expect(throws: RateLoader.Failure.self) {
            try await client.latestQuote(
                baseCurrency: .cny,
                currencies: Set(CurrencyCode.allCases)
            )
        }
    }

    private static let validResponse = FrankfurterExchangeRateClient.NetworkResponse(
        data: Data("""
        [
          {"date":"2026-09-23","base":"CNY","quote":"USD","rate":0.1403},
          {"date":"2026-09-23","base":"CNY","quote":"JPY","rate":20.81},
          {"date":"2026-09-22","base":"CNY","quote":"KWD","rate":0.04301},
          {"date":"2026-09-22","base":"CNY","quote":"EUR","rate":0.1288}
        ]
        """.utf8),
        statusCode: 200
    )
}

private actor RateLoader {
    struct Failure: Error {}

    enum Reply: Sendable {
        case success(FrankfurterExchangeRateClient.NetworkResponse)
        case failure
    }

    private let replies: [Reply]
    private(set) var requestedURLs: [URL] = []

    init(replies: [Reply]) {
        self.replies = replies
    }

    var callCount: Int { requestedURLs.count }

    func load(_ url: URL) throws -> FrankfurterExchangeRateClient.NetworkResponse {
        let index = requestedURLs.count
        requestedURLs.append(url)
        guard index < replies.count else { throw Failure() }
        switch replies[index] {
        case .success(let response):
            return response
        case .failure:
            throw Failure()
        }
    }
}
