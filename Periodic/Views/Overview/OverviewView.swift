import SwiftUI

struct OverviewView: View {
    @Bindable var session: WindowSession
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""
    @State private var selection = Set<SubscriptionListItem.ID>()

    private var items: [SubscriptionListItem] { session.filteredItems }
    private var analytics: SubscriptionAnalytics {
        SubscriptionAnalytics(items: items, referenceDate: session.referenceDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            quickViews
            Divider()
            table
            Divider()
            footer
        }
        .toolbar { toolbarContent }
        .accessibilityIdentifier("overview-page")
    }

    private var quickViews: some View {
        HStack(spacing: 12) {
            Picker("快捷视图", selection: $session.quickView) {
                ForEach(SubscriptionQuickView.allCases) { quickView in
                    Text(quickView.title).tag(quickView)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)

            Spacer()

            if session.quickView != .all || !session.searchText.isEmpty || session.hasOverviewFilters {
                Button("清除条件") {
                    session.quickView = .all
                    session.searchText = ""
                    session.clearOverviewFilters()
                }
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var table: some View {
        ZStack {
            Table(of: SubscriptionListItem.self, selection: $selection) {
                TableColumn("服务名称") { item in
                    Button {
                        session.presentDetails(for: item.id)
                    } label: {
                        HStack(spacing: 8) {
                            ServiceIconView(
                                iconResourceName: item.iconResourceName,
                                iconURLString: item.iconURLString,
                                fallbackSeed: item.name,
                                size: 22
                            )
                            Text(item.name)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .help("查看订阅详情")
                    .accessibilityLabel("查看 \(item.name) 的订阅详情")
                }
                .width(min: 140, ideal: 210, max: 210)

                TableColumnForEach(OverviewTextColumn.allCases) { column in
                    TableColumn(column.title) { item in
                        column.content(
                            for: item,
                            referenceDate: session.referenceDate,
                            currencyDisplayStyle: currencyDisplayStyle
                        )
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .width(
                        min: column.minimumWidth,
                        ideal: column.idealWidth,
                        max: column.maximumWidth
                    )
                }
            } rows: {
                switch session.grouping {
                case .none:
                    ForEach(items) { item in
                        TableRow(item)
                    }
                case .category:
                    ForEach(ServiceCategory.allCases) { category in
                        let groupedItems = items.filter { $0.categoryValue == category }
                        if !groupedItems.isEmpty {
                            Section("\(category.title)（\(groupedItems.count)）") {
                                ForEach(groupedItems) { item in
                                    TableRow(item)
                                }
                            }
                        }
                    }
                case .managementState:
                    ForEach(ManagementState.allCases) { state in
                        let groupedItems = items.filter { $0.managementState == state }
                        if !groupedItems.isEmpty {
                            Section("\(state.title)（\(groupedItems.count)）") {
                                ForEach(groupedItems) { item in
                                    TableRow(item)
                                }
                            }
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: SubscriptionListItem.ID.self) { selectedIDs in
                if let id = selectedIDs.first {
                    Button("订阅详情") {
                        session.presentDetails(for: id)
                    }
                    Button("编辑订阅") {
                        session.presentEditor(for: id)
                    }
                }
            } primaryAction: { selectedIDs in
                if let id = selectedIDs.first {
                    session.presentDetails(for: id)
                }
            }
            .onKeyPress(.return) {
                guard let id = selection.first else { return .ignored }
                session.presentDetails(for: id)
                return .handled
            }

            if items.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "rectangle.stack.badge.plus")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if session.items.isEmpty {
                        HStack {
                            Button("从模板添加") {
                                session.presentTemplateLibrary()
                            }
                            Button("空白新建") {
                                session.presentNewSubscription()
                            }
                        }
                    } else {
                        Button("清除条件") {
                            session.quickView = .all
                            session.searchText = ""
                            session.clearOverviewFilters()
                        }
                    }
                }
                .accessibilityIdentifier("overview-empty-state")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("当前结果 \(items.count) / 全库 \(session.items.count)")
                .accessibilityIdentifier("overview-result-count")
            Text(forecastSummary)
                .foregroundStyle(.secondary)
            Spacer()
            Text("停用 \(inactiveCount) · 终生 \(lifetimeCount) · 过期 \(expiredCount) · 日期未知 \(unknownDateCount)")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("空白新建") {
                    session.presentNewSubscription()
                }
                Button("从服务模板新建") {
                    session.presentTemplateLibrary()
                }
            } label: {
                Label("新建", systemImage: "plus")
            }

            Menu {
                Picker("管理状态", selection: $session.overviewManagementState) {
                    Text("全部管理状态").tag(nil as ManagementState?)
                    ForEach(ManagementState.allCases) { state in
                        Text(state.title).tag(Optional(state))
                    }
                }
                Picker("到期状态", selection: $session.overviewExpiryFilter) {
                    ForEach(OverviewExpiryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                Picker("服务类型", selection: $session.overviewCategory) {
                    Text("全部服务类型").tag(nil as ServiceCategory?)
                    ForEach(ServiceCategory.allCases) { category in
                        Text(category.title).tag(Optional(category))
                    }
                }
                Picker("计费类型", selection: $session.overviewBillingKind) {
                    Text("全部计费类型").tag(nil as BillingKind?)
                    ForEach(BillingKind.allCases) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                Picker("币种", selection: $session.overviewCurrency) {
                    Text("全部币种").tag(nil as CurrencyCode?)
                    ForEach(CurrencyPreferences.availableCurrencies(
                        from: selectedCurrenciesRaw,
                        including: session.overviewCurrency
                    )) { currency in
                        Text(currency.rawValue).tag(Optional(currency))
                    }
                }
                if session.hasOverviewFilters {
                    Divider()
                    Button("清除筛选") { session.clearOverviewFilters() }
                }
            } label: {
                Label(
                    "筛选",
                    systemImage: session.hasOverviewFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }

            Picker("分组", selection: $session.grouping) {
                ForEach(OverviewGrouping.allCases) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            .pickerStyle(.menu)

            Menu {
                Button("恢复默认列") {}
            } label: {
                Label("显示列", systemImage: "rectangle.split.3x1")
            }
            .disabled(true)

            ToolbarSearchButton(
                text: $session.searchText,
                prompt: "搜索订阅名称"
            )
        }
    }

    private var emptyTitle: String {
        session.items.isEmpty ? "还没有订阅" : "没有匹配的订阅"
    }

    private var emptyDescription: String {
        session.items.isEmpty
            ? "新建第一个订阅，到期日期和费用将同步出现在三个页面。"
            : "请调整搜索词或清除快捷视图条件。"
    }

    private var inactiveCount: Int { analytics.inactiveCount }
    private var lifetimeCount: Int { analytics.effectiveLifetimeCount }
    private var expiredCount: Int { analytics.expiredCount }
    private var unknownDateCount: Int { analytics.unknownDateCount }
    private var forecastSummary: String {
        analytics.forecastItems.isEmpty
            ? "无参与预估的周期订阅"
            : "周期订阅预估 \(analytics.forecastItems.count) 项"
    }
}

#Preview {
    NavigationStack {
        OverviewView(session: WindowSession())
    }
    .frame(width: 1100, height: 700)
}
