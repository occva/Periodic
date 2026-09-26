import Foundation

enum CurrencyPreferences {
    static let defaultCurrencies: [CurrencyCode] = [.cny, .jpy, .kwd, .usd]
    #if DEBUG || TEST_SUPPORT
    static let developmentSampleCurrencies = CurrencyCode.allCases
    #endif

    static func selectedCurrencies(
        from storedValue: String,
        useDevelopmentSampleCurrencies: Bool = isDevelopmentSampleDataEnabled
    ) -> [CurrencyCode] {
        #if DEBUG
        if useDevelopmentSampleCurrencies {
            return uniqueSorted(developmentSampleCurrencies)
        }
        #endif
        let currencies = storedValue
            .split(separator: ",")
            .compactMap { CurrencyCode(rawValue: String($0)) }
        return currencies.isEmpty ? defaultCurrencies : uniqueSorted(currencies)
    }

    static func storedValue(for currencies: some Sequence<CurrencyCode>) -> String {
        uniqueSorted(Array(currencies)).map(\.rawValue).joined(separator: ",")
    }

    static func canEditSelectedCurrencies(
        useDevelopmentSampleCurrencies: Bool = isDevelopmentSampleDataEnabled
    ) -> Bool {
        !useDevelopmentSampleCurrencies
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

    static var isDevelopmentSampleDataEnabled: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-store-in-memory") && arguments.contains("-seed-test-data")
        #else
        return false
        #endif
    }
}
