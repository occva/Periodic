import Testing
@testable import Periodic

struct CurrencyPreferencesTests {
    @Test func arbitraryISOCurrencyCodeRoundTrips() throws {
        let euro = try #require(CurrencyCode(rawValue: "eur"))

        #expect(euro.rawValue == "EUR")
        #expect(euro.scale == 2)
        #expect(CurrencyCode.jpy.scale == 0)
        #expect(CurrencyCode.kwd.scale == 3)
    }

    @Test func selectedCurrenciesUseDefaultsAndStableStorage() throws {
        #expect(CurrencyPreferences.selectedCurrencies(from: "") == [.cny, .jpy, .kwd, .usd])

        let euro = try #require(CurrencyCode(rawValue: "EUR"))
        let stored = CurrencyPreferences.storedValue(for: [.usd, euro, .cny, .usd])

        #expect(stored == "CNY,EUR,USD")
        #expect(CurrencyPreferences.selectedCurrencies(from: stored) == [.cny, euro, .usd])
    }

    @Test func currentUnselectedCurrencyRemainsAvailableForEditing() throws {
        let euro = try #require(CurrencyCode(rawValue: "EUR"))
        let available = CurrencyPreferences.availableCurrencies(
            from: "CNY,USD",
            including: euro
        )

        #expect(available == [.cny, euro, .usd])
    }
}
