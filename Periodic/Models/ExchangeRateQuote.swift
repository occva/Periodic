import Foundation

struct ExchangeRateQuote: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case identity
        case frankfurter
    }

    let baseCurrency: CurrencyCode
    let date: String
    let ratesPerBaseUnit: [CurrencyCode: Decimal]
    let isStale: Bool
    let source: Source

    func converting(_ amount: Decimal, from sourceCurrency: CurrencyCode) -> Decimal? {
        guard let rate = ratesPerBaseUnit[sourceCurrency], rate > 0 else { return nil }
        return amount / rate
    }

    func monthlyTotal(forecasts: [CurrencyForecast]) -> Decimal? {
        var total = Decimal.zero
        for forecast in forecasts {
            guard let converted = converting(forecast.monthly, from: forecast.currency) else {
                return nil
            }
            total += converted
        }
        return total
    }

    func annualTotal(forecasts: [CategoryForecast]) -> Decimal? {
        var total = Decimal.zero
        for forecast in forecasts {
            guard let converted = converting(forecast.annual, from: forecast.currency) else {
                return nil
            }
            total += converted
        }
        return total
    }

    var disclosure: String {
        guard source == .frankfurter else {
            return AppLocalization.string("所有金额均为默认货币，无需汇率换算。")
        }
        let freshness = isStale
            ? AppLocalization.string("缓存汇率")
            : AppLocalization.string("最新汇率")
        return String(
            format: AppLocalization.string("%@：Frankfurter v2 汇总央行参考汇率，数据日期 %@；仅请求币种代码，不发送订阅或金额。"),
            freshness,
            date
        )
    }
}
