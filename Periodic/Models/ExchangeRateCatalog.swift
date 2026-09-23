import Foundation

struct ExchangeRateCatalog: Codable, Equatable, Sendable {
    let baseCurrency: CurrencyCode
    let fetchedAt: Date
    let ratesPerBaseUnit: [String: Decimal]
    let datesByCurrency: [String: String]
    let isStale: Bool

    var rows: [ExchangeRateRow] {
        ratesPerBaseUnit
            .map {
                ExchangeRateRow(
                    currencyCode: $0.key,
                    rate: $0.value,
                    date: datesByCurrency[$0.key] ?? "—"
                )
            }
            .sorted { $0.currencyCode.localizedStandardCompare($1.currencyCode) == .orderedAscending }
    }

    var latestDate: String {
        datesByCurrency.values.max() ?? "—"
    }

    func dateDescription(for currencyCodes: [String]) -> String {
        let dates = Set(currencyCodes.compactMap { datesByCurrency[$0] }).sorted()
        guard let first = dates.first else { return "—" }
        guard let last = dates.last, last != first else { return first }
        return "\(first)–\(last)"
    }

    func withStaleStatus(_ isStale: Bool) -> ExchangeRateCatalog {
        ExchangeRateCatalog(
            baseCurrency: baseCurrency,
            fetchedAt: fetchedAt,
            ratesPerBaseUnit: ratesPerBaseUnit,
            datesByCurrency: datesByCurrency,
            isStale: isStale
        )
    }
}

struct ExchangeRateRow: Identifiable, Equatable, Sendable {
    let currencyCode: String
    let rate: Decimal
    let date: String

    var id: String { currencyCode }

    var localizedName: String {
        Locale.autoupdatingCurrent.localizedString(forCurrencyCode: currencyCode)
            ?? currencyCode
    }

    func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty
            || currencyCode.localizedStandardContains(normalized)
            || localizedName.localizedStandardContains(normalized)
    }
}
