import Foundation

struct SubscriptionRenewalRequest: Sendable {
    let subscriptionID: UUID
    let expectedRevision: Int64
    let expectedExpiry: LocalDate
}

struct SubscriptionRenewalPreview: Equatable, Sendable {
    let subscriptionID: UUID
    let expectedRevision: Int64
    let previousExpiry: LocalDate
    let nextStart: LocalDate
    let nextExpiry: LocalDate
    let cycleMonths: Int
    let money: Money
}

enum SubscriptionRenewalRule {
    enum RuleError: LocalizedError {
        case unavailable
        case notDue
        case invalidCycle
        case invalidDate

        var errorDescription: String? {
            switch self {
            case .unavailable: "只有使用中的周期订阅才能确认自动续费。"
            case .notDue: "尚未到续费确认日期。"
            case .invalidCycle: "订阅周期无效，无法计算下一周期。"
            case .invalidDate: "无法计算下一周期日期。"
            }
        }
    }

    static func preview(
        subscription: SubscriptionDTO,
        referenceDate: LocalDate
    ) throws -> SubscriptionRenewalPreview {
        guard subscription.managementState == .active,
              subscription.billingKind == .recurring,
              subscription.automaticallyRenews,
              let expiry = subscription.expiry else {
            throw RuleError.unavailable
        }
        guard referenceDate >= expiry else { throw RuleError.notDue }
        guard let cycleMonths = subscription.cycleMonths, cycleMonths > 0 else {
            throw RuleError.invalidCycle
        }
        guard let nextStart = expiry.addingDays(1),
              let followingStart = nextStart.addingMonths(cycleMonths),
              let nextExpiry = followingStart.addingDays(-1) else {
            throw RuleError.invalidDate
        }
        return SubscriptionRenewalPreview(
            subscriptionID: subscription.id,
            expectedRevision: subscription.revision,
            previousExpiry: expiry,
            nextStart: nextStart,
            nextExpiry: nextExpiry,
            cycleMonths: cycleMonths,
            money: subscription.money
        )
    }
}
