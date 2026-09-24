import Foundation

#if DEBUG
enum DevelopmentSubscriptionDataset {
    static let defaultCount = 240

    static func make(
        referenceDate: LocalDate,
        count: Int = defaultCount,
        templates: [ServiceTemplateDTO] = []
    ) -> [SubscriptionCreateInput] {
        let offsets = [
            -1_095, -730, -366, -365, -181, -91, -31, -30, -16, -15,
            -8, -7, -1, 0, 1, 7, 8, 15, 30, 31, 60, 90, 180, 365,
            366, 730, 1_095,
        ]
        let cycles = BillingCycle.allCases
        let currencies = CurrencyPreferences.developmentSampleCurrencies

        return (0..<max(0, count)).map { index in
            let template = templates.isEmpty ? nil : templates[index % templates.count]
            let isLifetime = index.isMultiple(of: 19)
            let isUndated = !isLifetime && index.isMultiple(of: 13)
            let isInactive = index.isMultiple(of: 17)
            let cycle = cycles[index % cycles.count]
            let currency = currencies[index % currencies.count]
            let expiry = isLifetime || isUndated
                ? nil
                : LocalDate(dayNumber: referenceDate.dayNumber + offsets[index % offsets.count])
            let periodStart = expiry.map {
                LocalDate(dayNumber: $0.dayNumber - max(1, cycle.rawValue * 30) + 1)
            } ?? (isLifetime ? LocalDate(dayNumber: referenceDate.dayNumber - index) : nil)
            let amount = Int64((index % 97) + 1) * minorUnitFactor(for: currency)

            return SubscriptionCreateInput(
                id: UUID(),
                name: sampleName(template: template, index: index, templateCount: templates.count),
                symbolName: template?.symbolName ?? "calendar.badge.clock",
                iconResourceName: template?.iconResourceName,
                iconURLString: template?.iconURLString,
                category: sampleCategory(template: template, index: index),
                managementState: isInactive ? .inactive : .active,
                billingKind: isLifetime ? .lifetime : .recurring,
                periodStart: periodStart,
                expiry: expiry,
                cycleMonths: isLifetime ? nil : cycle.rawValue,
                money: Money(minorUnits: amount, currency: currency),
                note: "多时间点测试数据 #\(index + 1)",
                reminderEnabled: !isLifetime
            )
        }
    }

    static func makeHistoricalPeriods(
        for subscriptions: [SubscriptionCreateInput]
    ) -> [SubscriptionPeriodCreateInput] {
        var periods: [SubscriptionPeriodCreateInput] = []

        for (index, subscription) in subscriptions.enumerated() {
            guard subscription.billingKind == .recurring,
                  let currentStart = subscription.periodStart,
                  subscription.expiry != nil else {
                continue
            }
            let historyCount = index % 5
            guard historyCount > 0 else { continue }
            let duration = max(1, (subscription.cycleMonths ?? 1) * 30)

            for occurrence in 1...historyCount {
                let end = LocalDate(dayNumber: currentStart.dayNumber - 1 - (occurrence - 1) * duration)
                let start = LocalDate(dayNumber: end.dayNumber - duration + 1)
                periods.append(SubscriptionPeriodCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    billingKind: .recurring,
                    cycleMonths: subscription.cycleMonths,
                    start: start,
                    end: end,
                    money: subscription.money
                ))
            }
        }

        return periods
    }

    private static func minorUnitFactor(for currency: CurrencyCode) -> Int64 {
        (0..<currency.scale).reduce(Int64(1)) { result, _ in result * 10 }
    }

    private static func sampleName(
        template: ServiceTemplateDTO?,
        index: Int,
        templateCount: Int
    ) -> String {
        guard let template, templateCount > 0 else {
            return String(format: "测试服务 %03d", index + 1)
        }
        let occurrence = index / templateCount + 1
        return occurrence == 1 ? template.name : "\(template.name) · \(occurrence)"
    }

    private static func sampleCategory(
        template: ServiceTemplateDTO?,
        index: Int
    ) -> ServiceCategory {
        if index.isMultiple(of: 31) {
            return .other
        }
        return template?.category ?? ServiceCategory.allCases[index % ServiceCategory.allCases.count]
    }
}
#endif
