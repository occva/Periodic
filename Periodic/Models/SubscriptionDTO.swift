import Foundation

struct SubscriptionDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let symbolName: String
    let iconResourceName: String?
    let iconURLString: String?
    let category: ServiceCategory
    let managementState: ManagementState
    let billingKind: BillingKind
    let periodStart: LocalDate?
    let expiry: LocalDate?
    let cycleMonths: Int?
    let money: Money
    let note: String
    let reminderEnabled: Bool
    let revision: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct SubscriptionPeriodDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let subscriptionID: UUID
    let billingKind: BillingKind
    let cycleMonths: Int?
    let start: LocalDate
    let end: LocalDate?
    let money: Money
    let createdAt: Date
}

struct SubscriptionPeriodCreateInput: Sendable {
    let id: UUID
    let subscriptionID: UUID
    let billingKind: BillingKind
    let cycleMonths: Int?
    let start: LocalDate
    let end: LocalDate?
    let money: Money
}

struct SubscriptionPeriodAddInput: Sendable {
    let period: SubscriptionPeriodCreateInput
    let expectedSubscriptionRevision: Int64
}

struct SubscriptionPeriodUpdateInput: Sendable {
    let original: SubscriptionPeriodDTO
    let expectedSubscriptionRevision: Int64
    let billingKind: BillingKind
    let cycleMonths: Int?
    let start: LocalDate
    let end: LocalDate?
    let money: Money
}

enum SubscriptionUpdateHistoryPolicy: Sendable {
    case currentOnly
    case appendPeriodRecord
}

struct SubscriptionCreateInput: Sendable {
    let id: UUID
    let name: String
    let symbolName: String
    let iconResourceName: String?
    let iconURLString: String?
    let category: ServiceCategory
    let managementState: ManagementState
    let billingKind: BillingKind
    let periodStart: LocalDate?
    let expiry: LocalDate?
    let cycleMonths: Int?
    let money: Money
    let note: String
    let reminderEnabled: Bool
}
