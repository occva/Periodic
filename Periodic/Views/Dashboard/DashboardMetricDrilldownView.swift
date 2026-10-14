import SwiftUI

struct DashboardMetricDrilldownView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle

    let scope: DashboardMetricScope
    let items: [SubscriptionListItem]
    let referenceDate: LocalDate
    let onDetails: (UUID) -> Void

    @State private var selection: SubscriptionListItem.ID?

    private var visibleItemIDs: Set<SubscriptionListItem.ID> {
        Set(items.map(\.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .frame(width: 760, height: 520)
        .presentationSizing(.fitted)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(scope.title, systemImage: scope.symbol)
                .font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var table: some View {
        ZStack {
            Table(of: SubscriptionListItem.self, selection: $selection) {
                TableColumn("服务名称") { item in
                    Button {
                        onDetails(item.id)
                    } label: {
                        HStack(spacing: 8) {
                            ServiceIconView(
                                iconResourceName: item.iconResourceName,
                                iconURLString: item.iconURLString,
                                fallbackSeed: item.name,
                                size: 22
                            )
                            Text(item.name)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("查看订阅详情")
                    .accessibilityLabel("查看 \(item.name) 的订阅详情")
                }
                .width(min: 160, ideal: 220)

                TableColumn("状态") { item in
                    Text(item.managementStatus(relativeTo: referenceDate))
                        .lineLimit(1)
                }
                .width(min: 72, ideal: 86, max: 100)

                TableColumn("周期") { item in
                    Text(item.billingKind)
                        .lineLimit(1)
                }
                .width(min: 72, ideal: 86, max: 110)

                TableColumn("到期时间") { item in
                    Text(item.expiryDate)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .width(min: 100, ideal: 110, max: 125)

                TableColumn("当前价格") { item in
                    Text(item.amount(style: currencyDisplayStyle))
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .width(min: 110, ideal: 125, max: 145)
            } rows: {
                ForEach(items) { item in
                    TableRow(item)
                }
            }
            .contextMenu(forSelectionType: SubscriptionListItem.ID.self) { selectedIDs in
                if let id = selectedIDs.first {
                    Button("订阅详情") {
                        onDetails(id)
                    }
                }
            } primaryAction: { selectedIDs in
                if let id = selectedIDs.first {
                    onDetails(id)
                }
            }
            .onKeyPress(.return) {
                guard let selection else { return .ignored }
                onDetails(selection)
                return .handled
            }
            .onChange(of: visibleItemIDs) { _, ids in
                if let selection, !ids.contains(selection) {
                    self.selection = nil
                }
            }

            if items.isEmpty {
                ContentUnavailableView(
                    scope.emptyTitle,
                    systemImage: scope.symbol,
                    description: Text("记录变化后，列表会与首页数量同步更新。")
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(itemCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("关闭", systemImage: "xmark") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.glass)
        }
        .padding(16)
    }

    private var itemCountText: String {
        String(
            format: AppLocalization.string("共 %d 项"),
            items.count
        )
    }
}

private extension DashboardMetricScope {
    var title: String {
        switch self {
        case .effective: AppLocalization.string("当前有效")
        case .expired: AppLocalization.string("已过期")
        }
    }

    var symbol: String {
        switch self {
        case .effective: "checkmark.circle"
        case .expired: "exclamationmark.circle"
        }
    }

    var emptyTitle: String {
        switch self {
        case .effective: AppLocalization.string("暂无当前有效订阅")
        case .expired: AppLocalization.string("暂无已过期订阅")
        }
    }
}
