import Foundation

enum CurrencyDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case code
    case symbol

    var id: String { rawValue }

    func format(_ number: String, currency: CurrencyCode) -> String {
        switch self {
        case .code:
            return "\(currency.rawValue) \(number)"
        case .symbol:
            let amount = currency == .kwd
                ? "\(currency.symbol) \(number)"
                : "\(currency.symbol)\(number)"
            guard let qualifier = currency.symbolQualifier else { return amount }
            return String(
                format: AppLocalization.string("%@（%@）"),
                amount,
                qualifier
            )
        }
    }

    func label(for currency: CurrencyCode) -> String {
        switch self {
        case .code: return currency.rawValue
        case .symbol:
            guard let qualifier = currency.symbolQualifier else { return currency.symbol }
            return String(
                format: AppLocalization.string("%@（%@）"),
                currency.symbol,
                qualifier
            )
        }
    }
}

extension CurrencyCode {
    var symbol: String {
        if self == .cny || self == .jpy { return "¥" }
        if self == .usd { return "$" }
        if self == .kwd { return "د.ك" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = rawValue
        return formatter.currencySymbol ?? rawValue
    }

    var symbolQualifier: String? {
        if self == .cny { return AppLocalization.string("人民币") }
        if self == .jpy { return AppLocalization.string("日元") }
        return nil
    }
}
