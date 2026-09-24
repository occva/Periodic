import Foundation
import SwiftData

@Model
final class SubscriptionRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbolName: String
    var iconResourceName: String?
    var iconURLString: String?
    var categoryRaw: String
    var managementStateRaw: String
    var billingKindRaw: String
    var periodStartDay: Int?
    var expiryDay: Int?
    var cycleMonths: Int?
    var periodAmountMinor: Int64
    var currencyCode: String
    var currencyScale: Int
    var note: String
    var reminderEnabled: Bool
    var automaticallyRenews: Bool = false
    var revision: Int64
    var createdAt: Date
    var updatedAt: Date

    init(input: SubscriptionCreateInput, now: Date = Date()) {
        id = input.id
        name = input.name
        symbolName = input.symbolName
        iconResourceName = input.iconResourceName
        iconURLString = input.iconURLString
        categoryRaw = input.category.rawValue
        managementStateRaw = input.managementState.rawValue
        billingKindRaw = input.billingKind.rawValue
        periodStartDay = input.periodStart?.dayNumber
        expiryDay = input.expiry?.dayNumber
        cycleMonths = input.cycleMonths
        periodAmountMinor = input.money.minorUnits
        currencyCode = input.money.currency.rawValue
        currencyScale = input.money.currency.scale
        note = input.note
        reminderEnabled = input.reminderEnabled
        automaticallyRenews = input.automaticallyRenews
        revision = 1
        createdAt = now
        updatedAt = now
    }

    func apply(_ input: SubscriptionCreateInput, now: Date = Date()) {
        name = input.name
        symbolName = input.symbolName
        iconResourceName = input.iconResourceName
        iconURLString = input.iconURLString
        categoryRaw = input.category.rawValue
        managementStateRaw = input.managementState.rawValue
        billingKindRaw = input.billingKind.rawValue
        periodStartDay = input.periodStart?.dayNumber
        expiryDay = input.expiry?.dayNumber
        cycleMonths = input.cycleMonths
        periodAmountMinor = input.money.minorUnits
        currencyCode = input.money.currency.rawValue
        currencyScale = input.money.currency.scale
        note = input.note
        reminderEnabled = input.reminderEnabled
        automaticallyRenews = input.automaticallyRenews
        revision += 1
        updatedAt = now
    }

    func markHistoryChanged(now: Date = Date()) {
        revision += 1
        updatedAt = now
    }

    func applyRenewal(
        start: LocalDate,
        expiry: LocalDate,
        now: Date = Date()
    ) {
        managementStateRaw = ManagementState.active.rawValue
        periodStartDay = start.dayNumber
        expiryDay = expiry.dayNumber
        revision += 1
        updatedAt = now
    }
}
