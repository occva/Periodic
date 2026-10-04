import Foundation

enum SubscriptionSharingPeriodSelection: Hashable {
    case current
    case period(UUID)

    static func initial(
        subscription: SubscriptionDTO,
        periods: [SubscriptionPeriodDTO],
        referenceDate: LocalDate = .today
    ) -> Self {
        let shared = periods.filter { $0.subscriptionID == subscription.id && $0.sharing != nil }
        if subscription.sharing != nil, let matching = shared.last(where: {
            $0.billingKind == subscription.billingKind
                && $0.start == subscription.periodStart && $0.end == subscription.expiry
        }) {
            return .period(matching.id)
        }
        if let active = shared.last(where: {
            $0.start <= referenceDate && ($0.end ?? .defaultLifetimeHistoryEnd) >= referenceDate
        }) {
            return .period(active.id)
        }
        if let latest = shared.last { return .period(latest.id) }
        return .current
    }
}
