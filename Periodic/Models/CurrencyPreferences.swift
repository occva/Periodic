import Foundation

enum CurrencyPreferences {
    static let defaultCurrencies: [CurrencyCode] = [.cny, .jpy, .kwd, .usd]

    static func selectedCurrencies(from storedValue: String) -> [CurrencyCode] {
        let currencies = storedValue
            .split(separator: ",")
            .compactMap { CurrencyCode(rawValue: String($0)) }
        return currencies.isEmpty ? defaultCurrencies : uniqueSorted(currencies)
    }

    static func storedValue(for currencies: some Sequence<CurrencyCode>) -> String {
        uniqueSorted(Array(currencies)).map(\.rawValue).joined(separator: ",")
    }

    static func availableCurrencies(
        from storedValue: String,
        including current: CurrencyCode? = nil
    ) -> [CurrencyCode] {
        var currencies = selectedCurrencies(from: storedValue)
        if let current, !currencies.contains(current) {
            currencies.append(current)
        }
        return uniqueSorted(currencies)
    }

    private static func uniqueSorted(_ currencies: [CurrencyCode]) -> [CurrencyCode] {
        Array(Set(currencies)).sorted { $0.rawValue < $1.rawValue }
    }
}
