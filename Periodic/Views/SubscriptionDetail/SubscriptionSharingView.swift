import SwiftUI

enum SubscriptionSharingPresentationStyle: Equatable {
    case standard
    case periodSheet
}

struct SubscriptionSharingView: View {
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    let plan: SubscriptionSharingPlan
    let myMoney: Money
    let presentationStyle: SubscriptionSharingPresentationStyle

    init(
        plan: SubscriptionSharingPlan,
        myMoney: Money,
        presentationStyle: SubscriptionSharingPresentationStyle = .standard
    ) {
        self.plan = plan
        self.myMoney = myMoney
        self.presentationStyle = presentationStyle
    }

    var body: some View {
        ScrollView {
            switch presentationStyle {
            case .standard:
                standardContent
                    .frame(maxWidth: 1200)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            case .periodSheet:
                periodSheetContent
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("subscription-sharing-detail")
    }

    @ViewBuilder
    private var standardContent: some View {
        switch plan.role {
        case .organizer:
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 32) {
                    memberQuotes
                        .frame(minWidth: 360, maxWidth: .infinity)
                    SubscriptionSharingPriceSummaryView(
                        plan: plan,
                        myMoney: myMoney,
                        presentationStyle: .standard
                    )
                    .frame(width: 360)
                }
                VStack(alignment: .leading, spacing: 28) {
                    SubscriptionSharingPriceSummaryView(
                        plan: plan,
                        myMoney: myMoney,
                        presentationStyle: .standard
                    )
                    memberQuotes
                }
            }
        case .participant:
            SubscriptionSharingPriceSummaryView(
                plan: plan,
                myMoney: myMoney,
                presentationStyle: .standard
            )
        }
    }

    private var periodSheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            SubscriptionSharingPriceSummaryView(
                plan: plan,
                myMoney: myMoney,
                presentationStyle: .periodSheet
            )

            if plan.role == .organizer {
                SubscriptionSharingSectionDivider()
                    .padding(.vertical, 18)
                memberQuotes
                SubscriptionSharingSectionDivider()
                    .padding(.top, 18)
            }
        }
    }

    private var memberQuotes: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("成员价格")
                    .font(.headline)
                Spacer()
                Text(String(format: AppLocalization.string("%d 人"), plan.memberCount))
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
            Text(name)
                .fontWeight(isMe ? .semibold : .regular)
                .textSelection(.enabled)
            Spacer(minLength: 12)
            switch presentationStyle {
            case .standard:
                Text(money?.displayText(style: currencyDisplayStyle) ?? AppLocalization.string("未填写"))
                    .fontWeight(isMe ? .semibold : .regular)
                    .foregroundStyle(money == nil ? .secondary : .primary)
                    .monospacedDigit()
                    .textSelection(.enabled)
            case .periodSheet:
                if let money {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(currencyDisplayStyle.label(for: money.currency))
                            .foregroundStyle(.secondary)
                        Text(Money.displayNumber(money.decimalValue, currency: money.currency))
                            .fontWeight(isMe ? .semibold : .regular)
                            .monospacedDigit()
                    }
                    .textSelection(.enabled)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(money.displayText(style: currencyDisplayStyle))
                } else {
                    Text("未填写")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 14)
    }
}

struct SubscriptionSharingSectionDivider: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0.5))
            }
            .stroke(
                Color.secondary.opacity(0.3),
                style: StrokeStyle(lineWidth: 1, dash: [6, 5])
            )
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}
