import SwiftUI

enum OverviewTextColumn: String, CaseIterable, Identifiable {
    case managementStatus
    case category
    case expiryDate
    case remainingDays
    case expiryStatus
    case billingKind
    case amount
    case monthlyEstimate
    case annualEstimate
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .managementStatus: AppLocalization.string("状态")
        case .category: AppLocalization.string("服务类型")
        case .expiryDate: AppLocalization.string("到期时间")
        case .remainingDays: AppLocalization.string("剩余时长")
        case .expiryStatus: AppLocalization.string("账户状态")
        case .billingKind: AppLocalization.string("周期")
        case .amount: AppLocalization.string("消费金额")
        case .monthlyEstimate: AppLocalization.string("按月计算")
        case .annualEstimate: AppLocalization.string("按年计算")
        case .note: AppLocalization.string("备注")
        }
    }

    var value: KeyPath<SubscriptionListItem, String> {
        switch self {
        case .managementStatus: \.managementStatus
        case .category: \.category
        case .expiryDate: \.expiryDate
        case .remainingDays: \.remainingDays
        case .expiryStatus: \.expiryStatus
        case .billingKind: \.billingKind
        case .amount: \.amount
        case .monthlyEstimate: \.monthlyEstimate
        case .annualEstimate: \.annualEstimate
        case .note: \.note
        }
    }

    @ViewBuilder
    func content(
        for item: SubscriptionListItem,
        referenceDate: LocalDate,
        currencyDisplayStyle: CurrencyDisplayStyle
    ) -> some View {
        switch self {
        case .remainingDays:
            RemainingDurationCell(item: item, referenceDate: referenceDate)
        case .amount:
            Text(item.amount(style: currencyDisplayStyle))
                .monospacedDigit()
        case .monthlyEstimate:
            Text(item.monthlyEstimate(style: currencyDisplayStyle))
                .monospacedDigit()
        case .annualEstimate:
            Text(item.annualEstimate(style: currencyDisplayStyle))
                .monospacedDigit()
        default:
            Text(item[keyPath: value])
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .amount: 130
        case .note: 140
        case .expiryDate, .monthlyEstimate, .annualEstimate: 100
        case .remainingDays: 140
        default: 84
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .amount: 150
        case .note: 220
        case .expiryDate: 112
        case .remainingDays: 150
        case .monthlyEstimate, .annualEstimate: 116
        default: 96
        }
    }
}

private struct RemainingDurationCell: View {
    let item: SubscriptionListItem
    let referenceDate: LocalDate

    var body: some View {
        HStack(spacing: 8) {
            Text(item.remainingDayCount(relativeTo: referenceDate).map(String.init) ?? "—")
                .frame(minWidth: 28, alignment: .trailing)
                .monospacedDigit()
            if let progress = item.remainingDaysProgress(relativeTo: referenceDate) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(progress > 0 ? .green : .secondary)
                    .frame(width: 100)
                    .help("按 100 天刻度显示剩余时间")
            }
        }
    }
}
