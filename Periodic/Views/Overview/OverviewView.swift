import SwiftUI

struct OverviewView: View {
    @Bindable var session: WindowSession
    @Environment(AppServices.self) private var services
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""
    @AppStorage(PreferenceKey.overviewVisibleColumns) private var visibleColumnsRaw = ""
    @AppStorage(PreferenceKey.overviewSortOption) private var sortOption =
        OverviewSortOption.remainingDaysDescending
    @State private var selection = Set<SubscriptionListItem.ID>()
    @State private var deletionPreview: SubscriptionDeletionPreview?
    @State private var isPreparingDeletion = false
    @State private var isDeleting = false
    @State private var error: PresentedError?
    @State private var collapsedGroupIDs = Set<String>()

    private var items: [SubscriptionListItem] {
        sortOption.sorted(session.filteredItems, referenceDate: session.referenceDate)
    }
    private var visibleItemIDs: Set<SubscriptionListItem.ID> { Set(items.map(\.id)) }
    private var actionableSelection: Set<SubscriptionListItem.ID> {
        OverviewSelection.visibleIDs(in: selection, items: items)
    }
    private var visibleColumns: [OverviewTextColumn] {
        let selected = OverviewColumnPreferences.visibleColumns(from: visibleColumnsRaw)
        return OverviewTextColumn.allCases.filter(selected.contains)
    }
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
        .errorAlert($error)
        .confirmationDialog(
            "永久删除所选订阅？",
            isPresented: Binding(
                get: { deletionPreview != nil },
                set: { if !$0 { deletionPreview = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletionPreview
        ) { preview in
            Button("永久删除", role: .destructive) { delete(preview) }
            Button("取消", role: .cancel) {}
        } message: { preview in
            Text(
                "将删除 \(preview.subscriptionCount) 条订阅、\(preview.periodCount) 条周期记录和 \(preview.paymentCount) 条消费记录。此操作无法撤销。"
            )
        }
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                if let sharing = item.sharing {
                                    Text(sharing.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
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

                TableColumnForEach(visibleColumns) { column in
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
                            Section(groupTitle(category.title, items: groupedItems)) {
                                if !collapsedGroupIDs.contains(categoryGroupID(category)) {
                                    ForEach(groupedItems) { item in
                                        TableRow(item)
                                    }
                                }
                            }
                        }
                    }
                case .managementState:
                    ForEach(ManagementState.allCases) { state in
                        let groupedItems = items.filter { $0.managementState == state }
                        if !groupedItems.isEmpty {
                            Section(groupTitle(state.title, items: groupedItems)) {
                                if !collapsedGroupIDs.contains(managementGroupID(state)) {
                                    ForEach(groupedItems) { item in
                                        TableRow(item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: SubscriptionListItem.ID.self) { selectedIDs in
                if selectedIDs.count == 1, let id = selectedIDs.first {
                    Button("订阅详情") {
                        session.presentDetails(for: id)
                    }
                    Button("编辑订阅") {
                        session.presentEditor(for: id)
                    }
                    Button("复制订阅") {
                        session.presentDuplicate(for: id)
                    }
                }
                if !selectedIDs.isEmpty {
                    Divider()
                    Button("停用所选订阅") {
                        updateManagementState(.inactive, ids: selectedIDs)
                    }
                    Button("恢复所选订阅") {
                        updateManagementState(.active, ids: selectedIDs)
                    }
                    Button(
                        selectedIDs.count == 1 ? "删除订阅…" : "删除 \(selectedIDs.count) 条订阅…",
                        role: .destructive
                    ) {
                        prepareDeletion(selectedIDs)
                    }
                }
            } primaryAction: { selectedIDs in
                if let id = selectedIDs.first {
                    session.presentDetails(for: id)
                }
            }
            .onKeyPress(.return) {
                guard let id = actionableSelection.first else { return .ignored }
                session.presentDetails(for: id)
                return .handled
            }
            .onChange(of: visibleItemIDs) { _, ids in
                selection.formIntersection(ids)
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

            Menu {
                Picker("分组", selection: $session.grouping) {
                    ForEach(OverviewGrouping.allCases) { grouping in
                        Text(grouping.title).tag(grouping)
                    }
                }
                if session.grouping != .none {
                    Divider()
                    Menu("折叠分组") {
                        ForEach(visibleGroupOptions, id: \.id) { option in
                            Toggle(
                                option.title,
                                isOn: collapsedGroupBinding(option.id)
                            )
                        }
                        Divider()
                        Button("展开全部") { collapsedGroupIDs.removeAll() }
                    }
                }
            } label: {
                Label(session.grouping.title, systemImage: "rectangle.3.group")
            }

            Menu {
                ForEach(OverviewTextColumn.allCases) { column in
                    Toggle(column.title, isOn: columnVisibilityBinding(column))
                }
                Divider()
                Button("恢复默认列") {
                    visibleColumnsRaw = ""
                }
            } label: {
                Label("显示列", systemImage: "rectangle.split.3x1")
            }

            Picker("排序", selection: $sortOption) {
                ForEach(OverviewSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            Menu {
                Button("选择全部结果") {
                    selection = Set(items.map(\.id))
                }
                Button("选择已过期项目") {
                    selection = Set(
                        items
                            .filter { analytics.status(of: $0) == .expired }
                            .map(\.id)
                    )
                }
                if actionableSelection.count == 1, let id = actionableSelection.first {
                    Divider()
                    Button("复制所选订阅") { session.presentDuplicate(for: id) }
                }
                if !actionableSelection.isEmpty {
                    Divider()
                    Button("停用所选订阅") {
                        updateManagementState(.inactive, ids: actionableSelection)
                    }
                    Button("恢复所选订阅") {
                        updateManagementState(.active, ids: actionableSelection)
                    }
                    Button("删除所选订阅…", role: .destructive) {
                        prepareDeletion(actionableSelection)
                    }
                }
            } label: {
                Label("批量操作", systemImage: "checklist")
            }
            .disabled(isPreparingDeletion || isDeleting || items.isEmpty)

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

    private func columnVisibilityBinding(_ column: OverviewTextColumn) -> Binding<Bool> {
        Binding(
            get: {
                OverviewColumnPreferences.visibleColumns(from: visibleColumnsRaw).contains(column)
            },
            set: { isVisible in
                var columns = OverviewColumnPreferences.visibleColumns(from: visibleColumnsRaw)
                if isVisible {
                    columns.insert(column)
                } else {
                    columns.remove(column)
                }
                visibleColumnsRaw = OverviewColumnPreferences.storedValue(for: columns)
            }
        )
    }

    private func prepareDeletion(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let targets = mutationTargets(for: ids)
        guard targets.count == ids.count else {
            error = PresentedError(
                SubscriptionStore.StoreError.notFound,
                title: "无法准备删除"
            )
            return
        }
        isPreparingDeletion = true
        Task { @MainActor in
            defer { isPreparingDeletion = false }
            do {
                deletionPreview = try await services.previewSubscriptionDeletion(
                    targets: targets
                )
            } catch {
                self.error = PresentedError(error, title: "无法准备删除")
            }
        }
    }

    private func delete(_ preview: SubscriptionDeletionPreview) {
        isDeleting = true
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                let outcome = try await services.deleteSubscriptions(preview)
                selection.subtract(preview.targets.map(\.id))
                deletionPreview = nil
                await session.reload(using: services)
                if outcome.pendingIconCleanupCount > 0
                    || outcome.pendingPaymentAttachmentCleanupCount > 0 {
                    self.error = PresentedError(
                        SubscriptionDeletionNotice.iconCleanupPending,
                        title: "订阅已删除"
                    )
                }
            } catch {
                self.error = PresentedError(error, title: "无法删除订阅")
            }
        }
    }

    private var visibleGroupOptions: [(id: String, title: String)] {
        switch session.grouping {
        case .none:
            []
        case .category:
            ServiceCategory.allCases.compactMap { category in
                guard items.contains(where: { $0.categoryValue == category }) else { return nil }
                return (categoryGroupID(category), category.title)
            }
        case .managementState:
            ManagementState.allCases.compactMap { state in
                guard items.contains(where: { $0.managementState == state }) else { return nil }
                return (managementGroupID(state), state.title)
            }
        }
    }

    private func categoryGroupID(_ category: ServiceCategory) -> String {
        "category.\(category.rawValue)"
    }

    private func managementGroupID(_ state: ManagementState) -> String {
        "management.\(state.rawValue)"
    }

    private func collapsedGroupBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { collapsedGroupIDs.contains(id) },
            set: { isCollapsed in
                if isCollapsed {
                    collapsedGroupIDs.insert(id)
                } else {
                    collapsedGroupIDs.remove(id)
                }
            }
        )
    }

    private func groupTitle(_ title: String, items: [SubscriptionListItem]) -> String {
        let totals = Dictionary(grouping: items, by: { $0.money.currency })
            .map { currency, values in
                let amount = values.reduce(Decimal.zero) { $0 + $1.money.decimalValue }
                return Money.display(amount, currency: currency, style: currencyDisplayStyle)
            }
            .sorted()
            .joined(separator: " · ")
        let subtotal = totals.isEmpty ? "" : " · \(totals)"
        return "\(title)（\(items.count)）\(subtotal)"
    }

    private func updateManagementState(_ state: ManagementState, ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let targets = mutationTargets(for: ids)
        guard targets.count == ids.count else {
            error = PresentedError(
                SubscriptionStore.StoreError.notFound,
                title: "无法更新订阅状态"
            )
            return
        }
        Task { @MainActor in
            do {
                try await services.setSubscriptionManagementState(
                    state,
                    targets: targets
                )
                await session.reload(using: services)
            } catch {
                self.error = PresentedError(error, title: "无法更新订阅状态")
            }
        }
    }

    private func mutationTargets(
        for ids: Set<UUID>
    ) -> [SubscriptionMutationTarget] {
        session.subscriptions.compactMap { subscription in
            guard ids.contains(subscription.id) else { return nil }
            return SubscriptionMutationTarget(
                id: subscription.id,
                expectedRevision: subscription.revision
            )
        }
    }
}

private enum SubscriptionDeletionNotice: LocalizedError {
    case iconCleanupPending

    var errorDescription: String? {
        "订阅数据已删除，但部分本地图片暂时无法清理；应用下次启动时会自动重试。"
    }
}

#Preview {
    NavigationStack {
        OverviewView(session: WindowSession())
    }
    .frame(width: 1100, height: 700)
}
