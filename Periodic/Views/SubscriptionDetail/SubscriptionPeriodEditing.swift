import Foundation

enum SubscriptionPeriodKind: String, CaseIterable, Identifiable {
    case monthly
    case quarterly
    case semiannual
    case annual
    case custom
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: BillingCycle.monthly.title
        case .quarterly: BillingCycle.quarterly.title
        case .semiannual: BillingCycle.semiannual.title
        case .annual: BillingCycle.annual.title
        case .custom: AppLocalization.string("自定义")
        case .lifetime: AppLocalization.string("终生")
        }
    }

    var billingKind: BillingKind {
        self == .lifetime ? .lifetime : .recurring
    }

    var cycleMonths: Int? {
        switch self {
        case .monthly: BillingCycle.monthly.rawValue
        case .quarterly: BillingCycle.quarterly.rawValue
        case .semiannual: BillingCycle.semiannual.rawValue
        case .annual: BillingCycle.annual.rawValue
        case .custom, .lifetime: nil
        }
    }

    init(period: SubscriptionPeriodDTO) {
        self.init(billingKind: period.billingKind, cycleMonths: period.cycleMonths)
    }

    init(billingKind: BillingKind, cycleMonths: Int?) {
        guard billingKind == .recurring else {
            self = .lifetime
            return
        }
        switch cycleMonths.flatMap(BillingCycle.init(rawValue:)) {
        case .monthly: self = .monthly
        case .quarterly: self = .quarterly
        case .semiannual: self = .semiannual
        case .annual: self = .annual
        case nil: self = .custom
        }
    }
}

struct SubscriptionPeriodDraft {
    let id: UUID
    let original: SubscriptionPeriodDTO?
    var kind: SubscriptionPeriodKind
    var startDate: Date
    var endDate: Date
    var amountText: String
    var currency: CurrencyCode

    var isCreating: Bool { original == nil }

    init(period: SubscriptionPeriodDTO) {
        id = period.id
        original = period
        kind = SubscriptionPeriodKind(period: period)
        startDate = period.start.date()
        endDate = period.end?.date() ?? period.start.date()
        amountText = period.money.inputText
        currency = period.money.currency
    }

    init(subscription: SubscriptionDTO) {
        let defaultStart = subscription.periodStart?.date() ?? Date()
        id = UUID()
        original = nil
        kind = SubscriptionPeriodKind(
            billingKind: subscription.billingKind,
            cycleMonths: subscription.cycleMonths
        )
        startDate = defaultStart
        endDate = subscription.billingKind == .lifetime
            ? LocalDate.defaultLifetimeHistoryEnd.date()
            : subscription.expiry?.date() ?? defaultStart
        amountText = subscription.money.inputText
        currency = subscription.money.currency
    }

    func addInput(
        subscriptionID: UUID,
        expectedSubscriptionRevision: Int64
    ) throws -> SubscriptionPeriodAddInput {
        guard isCreating else { throw SubscriptionPeriodEditError.invalidDraft }
        let values = try validatedValues()
        return SubscriptionPeriodAddInput(
            period: SubscriptionPeriodCreateInput(
                id: id,
                subscriptionID: subscriptionID,
                billingKind: kind.billingKind,
                cycleMonths: kind.cycleMonths,
                start: values.start,
                end: values.end,
                money: values.money
            ),
            expectedSubscriptionRevision: expectedSubscriptionRevision
        )
    }

    func updateInput(expectedSubscriptionRevision: Int64) throws -> SubscriptionPeriodUpdateInput {
        guard let original else { throw SubscriptionPeriodEditError.invalidDraft }
        let values = try validatedValues()
        return SubscriptionPeriodUpdateInput(
            original: original,
            expectedSubscriptionRevision: expectedSubscriptionRevision,
            billingKind: kind.billingKind,
            cycleMonths: kind.cycleMonths,
            start: values.start,
            end: values.end,
            money: values.money
        )
    }

    private func validatedValues() throws -> (start: LocalDate, end: LocalDate?, money: Money) {
        let start = LocalDate(startDate)
        let end = LocalDate(endDate)
        if start > end {
            throw SubscriptionPeriodEditError.invalidDateRange
        }
        let money = try Money.parse(amountText, currency: currency)
        return (start, end, money)
    }
}

private enum SubscriptionPeriodEditError: LocalizedError {
    case invalidDateRange
    case invalidDraft

    var errorDescription: String? {
        switch self {
        case .invalidDateRange: "结束时间不能早于开始时间。"
        case .invalidDraft: "周期记录草稿状态无效，请取消后重试。"
        }
    }
}

struct SubscriptionPeriodRow: Identifiable {
    let id: UUID
    let sequence: Int
    let period: SubscriptionPeriodDTO?

    var cycleTitle: String {
        guard let period else { return "—" }
        guard period.billingKind == .recurring else { return AppLocalization.string("终生") }
        return BillingCycle(rawValue: period.cycleMonths ?? 0)?.title
            ?? AppLocalization.string("自定义")
    }
}
