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
        switch self {
        case .cny: "¥"
        case .usd: "$"
        case .jpy: "¥"
        case .kwd: "د.ك"
        }
    }

    var symbolQualifier: String? {
        switch self {
        case .cny: AppLocalization.string("人民币")
        case .jpy: AppLocalization.string("日元")
        case .usd, .kwd: nil
        }
    }
}
