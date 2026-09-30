import Foundation
import Testing
@testable import Periodic

struct MoneyTests {
    @Test func malformedInputIsRejectedInsteadOfPartiallyParsed() {
        for text in [
            "12abc", "1,234.56", "12.3.4", "99元", "1e2xyz",
            "1 2", "1\n2", "1e", "1e+", "NaN", ".", "+",
        ] {
            #expect(throws: Money.ValidationError.invalid) {
                try Money.parse(text, currency: .cny)
            }
        }
    }

    @Test func completeDecimalInputPreservesSupportedNotation() throws {
        for text in ["12.50", " 12.50\n", "+12.50", "1.25e1"] {
            #expect(try Money.parse(text, currency: .cny).minorUnits == 1_250)
        }
        #expect(try Money.parse(".50", currency: .cny).minorUnits == 50)
        #expect(try Money.parse("1.", currency: .cny).minorUnits == 100)
        #expect(try Money.parse("0", currency: .cny).minorUnits == 0)
    }

    @Test func currencyPrecisionAndAmountLimitsRemainEnforced() throws {
        #expect(try Money.parse("1.234", currency: .kwd).minorUnits == 1_234)
        #expect(try Money.parse("123", currency: .jpy).minorUnits == 123)
        #expect(try Money.parse("92233720368547758.07", currency: .usd).minorUnits == Int64.max)
        #expect(throws: Money.ValidationError.empty) {
            try Money.parse(" \n", currency: .cny)
        }
        #expect(throws: Money.ValidationError.negative) {
            try Money.parse("-1", currency: .cny)
        }
        #expect(throws: Money.ValidationError.precision(2)) {
            try Money.parse("1.234", currency: .cny)
        }
        #expect(throws: Money.ValidationError.precision(0)) {
            try Money.parse("1.1", currency: .jpy)
        }
        #expect(throws: Money.ValidationError.overflow) {
            try Money.parse("92233720368547758.08", currency: .usd)
        }
    }
}
