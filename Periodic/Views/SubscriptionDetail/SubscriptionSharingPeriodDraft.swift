import Foundation

struct SubscriptionSharingPeriodDraft {
    var period: SubscriptionPeriodDraft
    var sharing: SubscriptionSharingDraft
    let subscriptionID: UUID
    let expectedRevision: Int64

    var id: UUID { period.id }
    var isCreating: Bool { period.isCreating }

    init(period: SubscriptionPeriodDTO, expectedRevision: Int64) throws {
        guard let plan = period.sharing else { throw SubscriptionSharingPeriodEditError.missingPlan }
        self.period = SubscriptionPeriodDraft(period: period)
        sharing = SubscriptionSharingDraft(plan: plan)
        subscriptionID = period.subscriptionID
        self.expectedRevision = expectedRevision
    }

    init(
        addingTo subscription: SubscriptionDTO,
        after previous: SubscriptionPeriodDTO?,
        referenceDate: LocalDate = .today
    ) throws {
        guard let plan = previous?.sharing ?? subscription.sharing else {
            throw SubscriptionSharingPeriodEditError.missingPlan
        }
        var period = SubscriptionPeriodDraft(subscription: subscription)
        if let previous {
            period.kind = SubscriptionPeriodKind(period: previous)
            period.amountText = previous.money.inputText
            period.currency = previous.money.currency
        }
        if period.kind == .lifetime {
            period.startDate = referenceDate.date()
            period.endDate = LocalDate.defaultLifetimeHistoryEnd.date()
        } else if let previous, let end = previous.end {
            guard let start = end.addingDays(1) else {
                throw SubscriptionSharingPeriodEditError.invalidDate
            }
            let nextEnd: LocalDate?
            if let months = period.kind.cycleMonths {
                nextEnd = start.addingMonths(months)?.addingDays(-1)
            } else {
                let duration = end.dayNumber.subtractingReportingOverflow(previous.start.dayNumber)
                guard !duration.overflow, duration.partialValue >= 0 else {
                    throw SubscriptionSharingPeriodEditError.invalidDate
                }
                nextEnd = start.addingDays(duration.partialValue)
            }
            guard let nextEnd else { throw SubscriptionSharingPeriodEditError.invalidDate }
            period.startDate = start.date()
            period.endDate = nextEnd.date()
        } else {
            let start = referenceDate
            let end: LocalDate?
            if let months = period.kind.cycleMonths {
                end = start.addingMonths(months)?.addingDays(-1)
            } else if let currentStart = subscription.periodStart,
                      let currentEnd = subscription.expiry {
                let duration = currentEnd.dayNumber.subtractingReportingOverflow(
                    currentStart.dayNumber
                )
                guard !duration.overflow, duration.partialValue >= 0 else {
                    throw SubscriptionSharingPeriodEditError.invalidDate
                }
                end = start.addingDays(duration.partialValue)
            } else {
                end = start
            }
            guard let end else {
                throw SubscriptionSharingPeriodEditError.invalidDate
            }
            period.startDate = start.date()
            period.endDate = end.date()
        }
        self.period = period
        sharing = SubscriptionSharingDraft(plan: plan)
        subscriptionID = subscription.id
        expectedRevision = subscription.revision
    }

    func pricePreview() throws -> (plan: SubscriptionSharingPlan, money: Money) {
        let money = try Money.parse(period.amountText, currency: period.currency)
        guard let plan = try sharing.plan(myMoney: money) else {
            throw SubscriptionSharingPeriodEditError.missingPlan
        }
        return (plan, money)
    }

    mutating func selectKind(_ kind: SubscriptionPeriodKind) {
        period.kind = kind
        if kind == .lifetime {
            period.endDate = LocalDate.defaultLifetimeHistoryEnd.date()
        } else if let months = kind.cycleMonths,
                  let end = LocalDate(period.startDate).addingMonths(months)?.addingDays(-1) {
            period.endDate = end.date()
        }
    }

    func addInput() throws -> SubscriptionPeriodAddInput {
        let base = try period.addInput(
            subscriptionID: subscriptionID,
            expectedSubscriptionRevision: expectedRevision
        ).period
        let preview = try pricePreview()
        return SubscriptionPeriodAddInput(
            period: SubscriptionPeriodCreateInput(
                id: base.id,
                subscriptionID: base.subscriptionID,
                billingKind: base.billingKind,
                cycleMonths: base.cycleMonths,
                start: base.start,
                end: base.end,
                money: preview.money,
                sharing: preview.plan,
                source: base.source
            ),
            expectedSubscriptionRevision: expectedRevision
        )
    }

    func updateInput() throws -> SubscriptionPeriodUpdateInput {
        let base = try period.updateInput(expectedSubscriptionRevision: expectedRevision)
        let preview = try pricePreview()
        return SubscriptionPeriodUpdateInput(
            original: base.original,
            expectedSubscriptionRevision: expectedRevision,
            billingKind: base.billingKind,
            cycleMonths: base.cycleMonths,
            start: base.start,
            end: base.end,
            money: preview.money,
            sharingUpdate: .replace(preview.plan)
        )
    }

    func overlappingPeriods(in periods: [SubscriptionPeriodDTO]) -> [SubscriptionPeriodDTO] {
        let start = LocalDate(period.startDate)
        let end = LocalDate(period.endDate)
        return periods.filter {
            $0.id != period.original?.id && $0.subscriptionID == subscriptionID
                && $0.start <= end && ($0.end ?? .defaultLifetimeHistoryEnd) >= start
        }
    }
}

enum SubscriptionSharingPeriodEditError: LocalizedError {
    case missingPlan
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .missingPlan: AppLocalization.string("本期没有拼车配置，请重新选择周期。")
        case .invalidDate: AppLocalization.string("无法计算下一期日期，请检查上一期的起止日期。")
        }
    }
}
