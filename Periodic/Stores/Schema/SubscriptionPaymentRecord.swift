import Foundation
import SwiftData

@Model
final class SubscriptionPaymentRecord {
    @Attribute(.unique) var id: UUID
    var subscriptionID: UUID
    var periodRecordID: UUID?
    var kindRaw: String
    var paymentDay: Int
    var amountMinor: Int64
    var currencyCode: String
    var currencyScale: Int
    var periodStartDay: Int?
    var periodEndDay: Int?
    var note: String
    var revision: Int64
    var createdAt: Date
    var updatedAt: Date

    init(input: SubscriptionPaymentCreateInput, now: Date = Date()) {
        id = input.id
        subscriptionID = input.subscriptionID
        periodRecordID = input.periodRecordID
        kindRaw = input.kind.rawValue
        paymentDay = input.paymentDate.dayNumber
        amountMinor = input.money.minorUnits
        currencyCode = input.money.currency.rawValue
        currencyScale = input.money.currency.scale
        periodStartDay = input.periodStart?.dayNumber
        periodEndDay = input.periodEnd?.dayNumber
        note = input.note
        revision = 1
        createdAt = now
        updatedAt = now
    }

    func apply(_ input: SubscriptionPaymentUpdateInput, now: Date = Date()) {
        periodRecordID = input.periodRecordID
        paymentDay = input.paymentDate.dayNumber
        amountMinor = input.money.minorUnits
        currencyCode = input.money.currency.rawValue
        currencyScale = input.money.currency.scale
        periodStartDay = input.periodStart?.dayNumber
        periodEndDay = input.periodEnd?.dayNumber
        note = input.note
        revision += 1
        updatedAt = now
    }
}
