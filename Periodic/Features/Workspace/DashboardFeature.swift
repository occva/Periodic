import Foundation
import Observation

@MainActor
@Observable
final class DashboardFeature {
    private(set) var exchangeRateQuote: ExchangeRateQuote?
    private(set) var exchangeRateError: PresentedError?
    private var generation = 0

    func loadExchangeRates(
        using client: FrankfurterExchangeRateClient,
        forecasts: [CategoryForecast],
        baseCurrency: CurrencyCode,
        referenceDate: LocalDate
    ) async {
        generation &+= 1
        let currentGeneration = generation
        let currencies = Set(forecasts.map(\.currency))
        guard !currencies.isEmpty else {
            exchangeRateQuote = nil
            exchangeRateError = nil
            return
        }
        if currencies == Set([baseCurrency]) {
            exchangeRateQuote = ExchangeRateQuote(
                baseCurrency: baseCurrency,
                date: referenceDate.displayText,
                ratesPerBaseUnit: [baseCurrency: 1],
                isStale: false,
                source: .identity
            )
            exchangeRateError = nil
            return
        }

        do {
            let quote = try await client.latestQuote(
                baseCurrency: baseCurrency,
                currencies: currencies
            )
            guard currentGeneration == generation else { return }
            exchangeRateQuote = quote
            exchangeRateError = nil
        } catch {
            guard currentGeneration == generation else { return }
            exchangeRateQuote = nil
            exchangeRateError = PresentedError(error, title: "无法更新汇率")
        }
    }
}
