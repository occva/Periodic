import Foundation

struct SubscriptionListItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let symbolName: String
    let iconResourceName: String?
    let iconURLString: String?
    let categoryValue: ServiceCategory
    let managementState: ManagementState
    let billingKindValue: BillingKind
    let periodStart: LocalDate?
    let expiry: LocalDate?
    let cycleMonths: Int?
    let money: Money
    let note: String
    let reminderEnabled: Bool
    let automaticallyRenews: Bool

    init(dto: SubscriptionDTO) {
        id = dto.id
        name = dto.name
        symbolName = dto.symbolName
        iconResourceName = dto.iconResourceName
        iconURLString = dto.iconURLString
        categoryValue = dto.category
        managementState = dto.managementState
        billingKindValue = dto.billingKind
        periodStart = dto.periodStart
        expiry = dto.expiry
        cycleMonths = dto.cycleMonths
        money = dto.money
        note = dto.note
        reminderEnabled = dto.reminderEnabled
        automaticallyRenews = dto.automaticallyRenews
    }

    var managementStatus: String {
        managementStatus(relativeTo: .today)
    }

    func managementStatus(relativeTo referenceDate: LocalDate) -> String {
        guard managementState == .active else { return AppLocalization.string("已停用") }
        if billingKindValue == .recurring,
           let remainingDays = remainingDayCount(relativeTo: referenceDate),
           remainingDays < 0 {
            return AppLocalization.string("已过期")
        }
        return AppLocalization.string(billingKindValue == .lifetime ? "使用中" : "订阅中")
    }

    var category: String { categoryValue.title }
    var expiryDate: String {
        switch billingKindValue {
        case .lifetime: AppLocalization.string("永久有效")
        case .recurring: expiry?.displayText ?? "—"
        }
    }

    var remainingDayCount: Int? {
        remainingDayCount(relativeTo: .today)
    }

    func remainingDayCount(relativeTo referenceDate: LocalDate) -> Int? {
        guard billingKindValue == .recurring, let expiry else { return nil }
        return expiry.dayNumber - referenceDate.dayNumber
    }

    func isPendingAutomaticRenewal(relativeTo referenceDate: LocalDate) -> Bool {
        guard managementState == .active,
              billingKindValue == .recurring,
              automaticallyRenews,
              let expiry,
              let cycleMonths else {
            return false
        }
        return cycleMonths > 0 && expiry <= referenceDate
    }

    var remainingDays: String { remainingDayCount.map(String.init) ?? "—" }

    func remainingDaysProgress(
        relativeTo referenceDate: LocalDate,
        fullScaleDays: Int = 100
    ) -> Double? {
        guard fullScaleDays > 0,
              let remainingDays = remainingDayCount(relativeTo: referenceDate) else {
            return nil
        }
        return min(max(Double(remainingDays) / Double(fullScaleDays), 0), 1)
    }

    var expiryStatus: String {
        expiryStatus(relativeTo: .today)
    }

    func expiryStatus(relativeTo referenceDate: LocalDate) -> String {
        guard billingKindValue == .recurring else { return AppLocalization.string("永久有效") }
        guard let days = remainingDayCount(relativeTo: referenceDate) else {
            return AppLocalization.string("日期未知")
        }
        return switch days {
        case ..<0: AppLocalization.string("已过期")
        case 0: AppLocalization.string("今天到期")
        default:
            String(
                format: AppLocalization.string("%d 天内"),
                days
            )
        }
    }

    var billingKind: String {
        guard billingKindValue == .recurring else { return AppLocalization.string("终生") }
        return BillingCycle(rawValue: cycleMonths ?? 1)?.title ?? AppLocalization.string("自定义")
    }

    var amount: String { money.displayText }
    func amount(style: CurrencyDisplayStyle) -> String {
        money.displayText(style: style)
    }

    func paymentSummary(style: CurrencyDisplayStyle) -> String {
        guard billingKindValue == .recurring, let cycleMonths else {
            return money.displayText(style: style)
        }
        let cadence = switch cycleMonths {
        case 1: AppLocalization.string("月付")
        case 3: AppLocalization.string("季付")
        case 6: AppLocalization.string("半年付")
        case 12: AppLocalization.string("年付")
        default:
            String(
                format: AppLocalization.string("每 %d 个月"),
                cycleMonths
            )
        }
        return "\(cadence) \(money.displayText(style: style))"
    }

    var monthlyEstimate: String {
        guard billingKindValue == .recurring, let cycleMonths else { return "—" }
        return money.monthlyEstimate(cycleMonths: cycleMonths)
    }

    func monthlyEstimate(style: CurrencyDisplayStyle) -> String {
        guard billingKindValue == .recurring, let cycleMonths else { return "—" }
        return money.monthlyEstimate(cycleMonths: cycleMonths, style: style)
    }

    var annualEstimate: String {
        guard billingKindValue == .recurring, let cycleMonths else { return "—" }
        return money.annualEstimate(cycleMonths: cycleMonths)
    }

    func annualEstimate(style: CurrencyDisplayStyle) -> String {
        guard billingKindValue == .recurring, let cycleMonths else { return "—" }
        return money.annualEstimate(cycleMonths: cycleMonths, style: style)
    }
}
