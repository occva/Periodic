import Foundation

enum SubscriptionSharingQuoteSummary: Equatable, Sendable {
    case complete(total: Money, purchaseDifference: Decimal?)
    case incomplete(unknownMemberCount: Int)
    case invalid

    init(plan: SubscriptionSharingPlan, myMoney: Money) {
        do {
            try plan.validate(myMoney: myMoney)
            if let total = try plan.quotedTotal(myMoney: myMoney) {
                self = .complete(
                    total: total,
                    purchaseDifference: plan.purchaseMoney.map {
                        total.decimalValue - $0.decimalValue
                    }
                )
            } else {
                self = .incomplete(
                    unknownMemberCount: plan.members.filter { $0.money == nil }.count
                )
            }
        } catch {
            self = .invalid
        }
    }
}
