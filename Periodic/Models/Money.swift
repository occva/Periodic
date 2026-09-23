import Foundation

struct Money: Hashable, Codable, Sendable {
    enum ValidationError: LocalizedError {
        case empty
        case invalid
        case negative
        case precision(Int)
        case overflow

        var errorDescription: String? {
            switch self {
            case .empty: "请输入金额。"
            case .invalid: "金额格式不正确。"
            case .negative: "金额不能为负数。"
            case .precision(let scale): "该币种最多支持 \(scale) 位小数。"
            case .overflow: "金额超出可保存范围。"
            }
        }
    }

    let minorUnits: Int64
    let currency: CurrencyCode

    static func parse(_ text: String, currency: CurrencyCode) throws -> Money {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ValidationError.empty }
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw ValidationError.invalid
        }
        guard decimal >= 0 else { throw ValidationError.negative }

        var original = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, currency.scale, .plain)
        guard rounded == decimal else { throw ValidationError.precision(currency.scale) }

        let factor = decimalPower(currency.scale)
        let scaled = decimal * factor
        let number = NSDecimalNumber(decimal: scaled)
        guard number != .notANumber,
              scaled <= Decimal(Int64.max),
              scaled >= Decimal(Int64.min) else {
            throw ValidationError.overflow
        }
        return Money(minorUnits: number.int64Value, currency: currency)
    }

    var displayText: String {
        displayText(style: .code)
    }

    func displayText(style: CurrencyDisplayStyle) -> String {
        style.format(
            formattedDecimal(decimalValue, scale: currency.scale),
            currency: currency
        )
    }

    var inputText: String {
        formattedDecimal(decimalValue, scale: currency.scale)
    }

    func monthlyEstimate(
        cycleMonths: Int,
        style: CurrencyDisplayStyle = .code
    ) -> String {
        let value = decimalValue / Decimal(cycleMonths)
        return style.format(formattedDecimal(value, scale: currency.scale), currency: currency)
    }

    func annualEstimate(
        cycleMonths: Int,
        style: CurrencyDisplayStyle = .code
    ) -> String {
        let value = decimalValue * 12 / Decimal(cycleMonths)
        return style.format(formattedDecimal(value, scale: currency.scale), currency: currency)
    }

    func monthlyAmount(cycleMonths: Int) -> Decimal {
        decimalValue / Decimal(cycleMonths)
    }

    func annualAmount(cycleMonths: Int) -> Decimal {
        decimalValue * 12 / Decimal(cycleMonths)
    }

    static func display(
        _ amount: Decimal,
        currency: CurrencyCode,
        style: CurrencyDisplayStyle = .code
    ) -> String {
        style.format(formattedDecimal(amount, scale: currency.scale), currency: currency)
    }

    static func displayNumber(_ amount: Decimal, currency: CurrencyCode) -> String {
        formattedDecimal(amount, scale: currency.scale)
    }

    private var decimalValue: Decimal {
        Decimal(minorUnits) / decimalPower(currency.scale)
    }
}

private func decimalPower(_ exponent: Int) -> Decimal {
    (0..<exponent).reduce(Decimal(1)) { result, _ in result * 10 }
}

private func formattedDecimal(_ value: Decimal, scale: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = scale
    formatter.maximumFractionDigits = scale
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
}
