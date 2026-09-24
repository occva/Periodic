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
    let automaticallyRenews: Bool
    let revision: Int64
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        name: String,
        symbolName: String,
        iconResourceName: String?,
        iconURLString: String?,
        category: ServiceCategory,
        managementState: ManagementState,
        billingKind: BillingKind,
        periodStart: LocalDate?,
        expiry: LocalDate?,
        cycleMonths: Int?,
        money: Money,
        note: String,
        reminderEnabled: Bool,
        automaticallyRenews: Bool = false,
        revision: Int64,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.iconResourceName = iconResourceName
        self.iconURLString = iconURLString
        self.category = category
        self.managementState = managementState
        self.billingKind = billingKind
        self.periodStart = periodStart
        self.expiry = expiry
        self.cycleMonths = cycleMonths
        self.money = money
        self.note = note
        self.reminderEnabled = reminderEnabled
        self.automaticallyRenews = automaticallyRenews
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SubscriptionPeriodDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let subscriptionID: UUID
    let billingKind: BillingKind
    let cycleMonths: Int?
    let start: LocalDate
    let end: LocalDate?
    let money: Money
    let source: SubscriptionPeriodSource
    let createdAt: Date

    init(
        id: UUID,
        subscriptionID: UUID,
        billingKind: BillingKind,
        cycleMonths: Int?,
        start: LocalDate,
        end: LocalDate?,
        money: Money,
        source: SubscriptionPeriodSource = .manual,
        createdAt: Date
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.billingKind = billingKind
        self.cycleMonths = cycleMonths
        self.start = start
        self.end = end
        self.money = money
        self.source = source
        self.createdAt = createdAt
    }
}

enum SubscriptionPeriodSource: String, Codable, Sendable {
    case initial
    case renewal
    case manual
    case legacy
}

struct SubscriptionPeriodCreateInput: Sendable {
    let id: UUID
    let subscriptionID: UUID
    let billingKind: BillingKind
    let cycleMonths: Int?
    let start: LocalDate
    let end: LocalDate?
    let money: Money
    let source: SubscriptionPeriodSource

    init(
        id: UUID,
        subscriptionID: UUID,
        billingKind: BillingKind,
        cycleMonths: Int?,
        start: LocalDate,
        end: LocalDate?,
        money: Money,
        source: SubscriptionPeriodSource = .manual
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.billingKind = billingKind
        self.cycleMonths = cycleMonths
        self.start = start
        self.end = end
        self.money = money
        self.source = source
    }
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
    let automaticallyRenews: Bool

    init(
        id: UUID,
        name: String,
        symbolName: String,
        iconResourceName: String?,
        iconURLString: String?,
        category: ServiceCategory,
        managementState: ManagementState,
        billingKind: BillingKind,
        periodStart: LocalDate?,
        expiry: LocalDate?,
        cycleMonths: Int?,
        money: Money,
        note: String,
        reminderEnabled: Bool,
        automaticallyRenews: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.iconResourceName = iconResourceName
        self.iconURLString = iconURLString
        self.category = category
        self.managementState = managementState
        self.billingKind = billingKind
        self.periodStart = periodStart
        self.expiry = expiry
        self.cycleMonths = cycleMonths
        self.money = money
        self.note = note
        self.reminderEnabled = reminderEnabled
        self.automaticallyRenews = automaticallyRenews
            && managementState == .active
            && billingKind == .recurring
            && expiry != nil
            && (cycleMonths ?? 0) > 0
    }
}
