import SwiftUI

struct SubscriptionDetailHeaderView: View {
    let subscription: SubscriptionDTO
    let canConfirmRenewal: Bool
    let isConfirmingRenewal: Bool
    let onMarkNotRenewed: @MainActor () -> Void
    let onConfirmRenewal: @MainActor () -> Void
    let onEditSubscription: @MainActor () -> Void

    private var item: SubscriptionListItem {
        SubscriptionListItem(dto: subscription)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                identity
                    .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                actions
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 16) {
                identity
                HStack {
                    Spacer()
                    actions
                }
            }
        }
        .padding(20)
    }

    private var identity: some View {
        HStack(spacing: 16) {
            ServiceIconView(
                iconResourceName: subscription.iconResourceName,
                iconURLString: subscription.iconURLString,
                fallbackSeed: subscription.name,
                size: 56
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(subscription.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text(item.managementStatus)
                        Text(subscription.category.title)
                        Text(expiryTitle)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.managementStatus)
                            Text(subscription.category.title)
                        }
                        Text(expiryTitle)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            renewalActions
            Button("编辑订阅", action: onEditSubscription)
                .buttonStyle(.glass)
        }
    }

    private var expiryTitle: String {
        guard subscription.billingKind == .recurring, subscription.expiry != nil else {
            return item.expiryDate
        }
        return String(format: AppLocalization.string("到期 %@"), item.expiryDate)
    }

    @ViewBuilder
    private var renewalActions: some View {
        if subscription.automaticallyRenews {
            if canConfirmRenewal {
                Button("未续费", action: onMarkNotRenewed)
                    .disabled(isConfirmingRenewal)
                    .buttonStyle(.glass)

                Button("已续费", action: onConfirmRenewal)
                .disabled(isConfirmingRenewal)
                .buttonStyle(.glassProminent)
                .accessibilityHint("更新当前周期并添加续费周期和消费记录")
            } else {
                Text(AppLocalization.string(subscription.sharing == nil
                    ? "服务商自动续费"
                    : "拼车续期确认"))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
