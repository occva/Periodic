import Foundation
import SwiftData

@Model
final class SubscriptionPeriodRecord {
    @Attribute(.unique) var id: UUID
    var subscriptionID: UUID
    var billingKindRaw: String
    var cycleMonths: Int?
    var startDay: Int
    var endDay: Int?
    var amountMinor: Int64
    var currencyCode: String
    var currencyScale: Int
    var createdAt: Date

    init(input: SubscriptionPeriodCreateInput, now: Date = Date()) {
        id = input.id
        subscriptionID = input.subscriptionID
        billingKindRaw = input.billingKind.rawValue
        cycleMonths = input.cycleMonths
        startDay = input.start.dayNumber
        endDay = input.end?.dayNumber
        amountMinor = input.money.minorUnits
        currencyCode = input.money.currency.rawValue
        currencyScale = input.money.currency.scale
        createdAt = now
    }

    func apply(_ input: SubscriptionPeriodUpdateInput) {
        billingKindRaw = input.billingKind.rawValue
        cycleMonths = input.cycleMonths
        startDay = input.start.dayNumber
        endDay = input.end?.dayNumber
        amountMinor = input.money.minorUnits
        currencyCode = input.money.currency.rawValue
        currencyScale = input.money.currency.scale
    }
}
