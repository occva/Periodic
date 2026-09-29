import Foundation

enum SubscriptionPaymentKind: String, Codable, CaseIterable, Sendable {
    case initial
    case renewal
    case manual

    var title: String {
        switch self {
        case .initial: AppLocalization.string("首次付款")
        case .renewal: AppLocalization.string("续费消费")
        case .manual: AppLocalization.string("消费")
        }
    }
}

struct SubscriptionPaymentDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let subscriptionID: UUID
    let periodRecordID: UUID?
    let kind: SubscriptionPaymentKind
    let paymentDate: LocalDate
    let money: Money
    let periodStart: LocalDate?
    let periodEnd: LocalDate?
    let note: String
    let attachmentReferences: [String]
    let revision: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct SubscriptionPaymentCreateInput: Sendable {
    let id: UUID
    let subscriptionID: UUID
    let periodRecordID: UUID?
    let kind: SubscriptionPaymentKind
    let paymentDate: LocalDate
    let money: Money
    let periodStart: LocalDate?
    let periodEnd: LocalDate?
    let note: String
    let attachmentReferences: [String]
}

struct SubscriptionPaymentAddInput: Sendable {
    let payment: SubscriptionPaymentCreateInput
    let expectedSubscriptionRevision: Int64
}

struct SubscriptionPaymentUpdateInput: Sendable {
    let original: SubscriptionPaymentDTO
    let expectedSubscriptionRevision: Int64
    let periodRecordID: UUID?
    let paymentDate: LocalDate
    let money: Money
    let periodStart: LocalDate?
    let periodEnd: LocalDate?
    let note: String
    let attachmentReferences: [String]
}

struct SubscriptionPaymentDeleteInput: Sendable {
    let original: SubscriptionPaymentDTO
    let expectedSubscriptionRevision: Int64
}

struct SubscriptionDetailSnapshot: Sendable {
    let subscription: SubscriptionDTO
    let periods: [SubscriptionPeriodDTO]
    let payments: [SubscriptionPaymentDTO]
}
