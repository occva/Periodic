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
                HStack(spacing: 8) {
                    Text(item.managementStatus)
                    Text(subscription.category.title)
                    Text(item.expiryDate)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            renewalActions
            Button("编辑订阅", systemImage: "pencil", action: onEditSubscription)
                .buttonStyle(.glass)
        }
        .padding(20)
    }

    @ViewBuilder
    private var renewalActions: some View {
        if subscription.automaticallyRenews {
            if canConfirmRenewal {
                Button("未续费", systemImage: "xmark", action: onMarkNotRenewed)
                    .disabled(isConfirmingRenewal)
                    .buttonStyle(.glass)

                Button(
                    "已续费",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    action: onConfirmRenewal
                )
                .disabled(isConfirmingRenewal)
                .buttonStyle(.glassProminent)
                .accessibilityHint("更新当前周期并添加一条续费周期记录")
            } else {
                Label("服务商自动续费", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
