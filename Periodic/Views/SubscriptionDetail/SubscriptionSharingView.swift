import SwiftUI

struct SubscriptionSharingView: View {
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    let plan: SubscriptionSharingPlan
    let myMoney: Money

    var body: some View {
        ScrollView {
            Group {
                switch plan.role {
                case .organizer:
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 32) {
                            memberQuotes
                                .frame(minWidth: 360, maxWidth: .infinity)
                            SubscriptionSharingPriceSummaryView(plan: plan, myMoney: myMoney)
                                .frame(minWidth: 420, maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 28) {
                            SubscriptionSharingPriceSummaryView(plan: plan, myMoney: myMoney)
                            memberQuotes
                        }
                    }
                case .participant:
                    SubscriptionSharingPriceSummaryView(plan: plan, myMoney: myMoney)
                }
            }
            .padding(24)
        }
        .accessibilityIdentifier("subscription-sharing-detail")
    }

    private var memberQuotes: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("成员价格")
                    .font(.headline)
                Spacer()
                Text(String(format: AppLocalization.string("%d 人（含我）"), plan.memberCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 18)

            HStack {
                Text("成员")
                Spacer()
                Text("约定价格")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
            Divider()

            quoteRow(name: AppLocalization.string("我"), money: myMoney, isMe: true)
            ForEach(plan.members) { member in
                Divider()
                quoteRow(name: member.name, money: member.money, isMe: false)
            }
        }
    }

    private func quoteRow(name: String, money: Money?, isMe: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .fontWeight(isMe ? .semibold : .regular)
                    .textSelection(.enabled)
                if isMe {
                    Text("本人")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(money?.displayText(style: currencyDisplayStyle) ?? AppLocalization.string("未填写"))
                .fontWeight(isMe ? .semibold : .regular)
                .foregroundStyle(money == nil ? .secondary : .primary)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .padding(.vertical, 14)
    }

}
