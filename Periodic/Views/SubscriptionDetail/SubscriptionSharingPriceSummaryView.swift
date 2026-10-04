import SwiftUI

struct SubscriptionSharingPriceSummaryView: View {
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    let plan: SubscriptionSharingPlan
    let myMoney: Money

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("价格汇总")
                    .font(.headline)
                Spacer()
                Text(plan.role.title)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel(AppLocalization.string("我的身份") + ": " + plan.role.title)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("我的价格")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(myMoney.displayText(style: currencyDisplayStyle))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .textSelection(.enabled)
                Text("用于个人费用预估")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if plan.role == .organizer {
                organizerSummary
            } else {
                summaryValue(
                    title: "拼车人数",
                    value: String(format: AppLocalization.string("%d 人（含我）"), plan.memberCount)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var organizerSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()

            switch SubscriptionSharingQuoteSummary(plan: plan, myMoney: myMoney) {
            case .complete(let total, let purchaseDifference):
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 0), alignment: .topLeading), count: 3),
                    alignment: .leading,
                    spacing: 12
                ) {
                    purchaseSummaryValue
                    summaryValue(
                        title: "成员价格合计",
                        value: total.displayText(style: currencyDisplayStyle)
                    )
                    if let purchaseDifference {
                        summaryValue(
                            title: "价格差额",
                            value: Money.display(
                                purchaseDifference,
                                currency: total.currency,
                                style: currencyDisplayStyle
                            )
                        )
                    }
                }
                if purchaseDifference != nil {
                    Text("成员价格合计减去订阅总价")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .incomplete(let unknownMemberCount):
                purchaseSummaryValue
                VStack(alignment: .leading, spacing: 4) {
                    Text("成员价格尚未齐全")
                        .font(.callout.weight(.medium))
                    Text(String(
                        format: AppLocalization.string("还有 %d 位成员未填写价格，暂不计算合计。"),
                        unknownMemberCount
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            case .invalid:
                purchaseSummaryValue
                Text("价格合计无法计算，请检查成员金额。")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Divider()
            Text("约定价格不代表已收付款。个人预估按我的价格计算；实际支出只统计已登记付款。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var purchaseSummaryValue: some View {
        summaryValue(
            title: "订阅总价",
            value: plan.purchaseMoney?.displayText(style: currencyDisplayStyle)
                ?? AppLocalization.string("未填写")
        )
    }

    private func summaryValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
