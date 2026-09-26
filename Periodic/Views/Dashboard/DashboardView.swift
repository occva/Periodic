import SwiftUI

struct DashboardView: View {
    @Bindable var session: WindowSession
    @Environment(AppServices.self) private var services
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @AppStorage(PreferenceKey.exchangeRateBaseCurrency) private var baseCurrency = CurrencyCode.cny
    @State private var feature = DashboardFeature()
    @State private var expandedCategories = Set<ServiceCategory>()
    @State private var upcomingScope = DashboardUpcomingScope.active
    @State private var forecastTooltipItemID: UUID?
    @State private var forecastTooltipTask: Task<Void, Never>?

    private var analytics: SubscriptionAnalytics { session.analytics }

    var body: some View {
        ViewThatFits(in: .vertical) {
            dashboardContent
            ScrollView {
                dashboardContent
            }
            .scrollIndicators(.hidden)
        }
        .toolbar { toolbarContent }
        .task(id: categoryExchangeRateRequestID) {
            await loadCategoryExchangeRates()
        }
        .onDisappear {
            forecastTooltipTask?.cancel()
        }
        .accessibilityIdentifier("dashboard-page")
    }

    private var dashboardContent: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                overviewSection
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        forecastCard
                        upcomingCard
                    }
                    GridRow {
                        categoryCard
                            .gridCellColumns(2)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
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
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("概况").font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                SummaryMetricCard(
                    title: "当前有效",
                    value: "\(analytics.effectiveRecurringCount + analytics.effectiveLifetimeCount)",
                    detail: "周期 \(analytics.effectiveRecurringCount) · 终生 \(analytics.effectiveLifetimeCount)",
                    symbol: "checkmark.circle",
                    valueAccessibilityIdentifier: "dashboard-active-count"
                )
                SummaryMetricCard(
                    title: "本月预估",
                    value: monthlyForecastText,
                    symbol: "banknote"
                )
                .help(monthlyForecastHelp)
                SummaryMetricCard(title: "已过期", value: "\(analytics.expiredCount)", symbol: "exclamationmark.circle")
                SummaryMetricCard(
                    title: "待续费",
                    value: "\(session.automaticRenewalDueItems.count)",
                    detail: "到期自动续费",
                    symbol: "checkmark.message",
                    action: { session.presentReminderCenter(scope: .pendingRenewal) }
                )
            }
        }
    }

    private var forecastCard: some View {
        DashboardCard(title: "预估费用", symbol: "banknote") {
            Group {
                if currencyForecasts.isEmpty {
                    Text("暂无费用数据")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(currencyForecasts) { forecast in
                                HStack(spacing: 12) {
                                    Text(currencyDisplayStyle.label(for: forecast.currency))
                                        .font(.headline)
                                    currencyForecastIcons(for: forecast.currency)
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(
                                            "月均 \(Money.display(forecast.monthly, currency: forecast.currency, style: currencyDisplayStyle))"
                                        )
                                        Text(
                                            "年化 \(Money.display(forecast.annual, currency: forecast.currency, style: currencyDisplayStyle))"
                                        )
                                            .foregroundStyle(.secondary)
                                    }
                                    .monospacedDigit()
                                }
                                .frame(height: DashboardLayout.currencyForecastRowHeight)
                                if forecast.id != currencyForecasts.last?.id { Divider() }
                            }
                        }
                    }
                    .defaultScrollAnchor(.top)
                    .dashboardScrollIndicatorGutter()
                }
            }
            .frame(height: DashboardLayout.primaryCardContentHeight)
        }
    }

    private var upcomingCard: some View {
        DashboardCard(
            title: upcomingScope.title,
            symbol: "clock",
            headerAccessory: {
                Picker("订阅范围", selection: $upcomingScope) {
                    ForEach(DashboardUpcomingScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    if upcomingScope == .upcoming {
                        HStack(spacing: 12) {
                            Spacer()
                            Text("临期范围")
                                .font(.headline)
                            Picker("临期范围", selection: $session.dueHorizon) {
                                ForEach(DueHorizon.allCases) { horizon in
                                    Text(horizon.title).tag(horizon)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                    }
                    subscriptionList
                }
                .frame(height: DashboardLayout.primaryCardContentHeight, alignment: .top)
            }
        )
    }

    @ViewBuilder
    private var subscriptionList: some View {
        Group {
            if displayedUpcomingItems.isEmpty {
                Text(upcomingScope.emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedUpcomingItems) { item in
                            HStack(spacing: 8) {
                                Button {
                                    session.presentDetails(for: item.id)
                                } label: {
                                    ServiceIconView(
                                        iconResourceName: item.iconResourceName,
                                        iconURLString: item.iconURLString,
                                        fallbackSeed: item.name,
                                        size: 22
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("查看订阅详情")
                                .accessibilityLabel("查看 \(item.name) 的订阅详情")
                                Text(item.name)
                                Spacer()
                                Text(item.expiryDate)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                session.presentDetails(for: item.id)
                            }
                            .contextMenu {
                                Button("订阅详情") {
                                    session.presentDetails(for: item.id)
                                }
                                Button("编辑订阅") {
                                    session.presentEditor(for: item.id)
                                }
                            }
                        }
                    }
                }
                .dashboardScrollIndicatorGutter()
            }
        }
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 4) {
            Text("共 \(displayedUpcomingItems.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var categoryCard: some View {
        DashboardCard(title: "服务类型年化", symbol: "chart.bar.xaxis") {
            if categoryForecastGroups.isEmpty {
                Text("暂无费用数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                IndependentColumnLayout(minimumColumnWidth: 220, spacing: 12) {
                    ForEach(categoryForecastGroups) { group in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedCategories.contains(group.category) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedCategories.insert(group.category)
                                    } else {
                                        expandedCategories.remove(group.category)
                                    }
                                }
                            )
                        ) {
                            VStack(spacing: 6) {
                                ForEach(categoryItems(for: group.category)) { item in
                                    HStack(spacing: 8) {
                                        Button {
                                            session.presentDetails(for: item.id)
                                        } label: {
                                            ServiceIconView(
                                                iconResourceName: item.iconResourceName,
                                                iconURLString: item.iconURLString,
                                                fallbackSeed: item.name,
                                                size: 20
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("查看 \(item.name) 的订阅详情")
                                        Text(item.name).lineLimit(1)
                                        Spacer()
                                        Text(
                                            item.money.annualEstimate(
                                                cycleMonths: item.cycleMonths ?? 1,
                                                style: currencyDisplayStyle
                                            )
                                        )
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        Button("订阅详情") { session.presentDetails(for: item.id) }
                                        Button("编辑订阅") { session.presentEditor(for: item.id) }
                                    }
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                Text(group.category.title)
                                Spacer()
                                Text(categoryAmount(for: group))
                                    .monospacedDigit()
                            }
                        }
                        .padding(10)
                        .help(categoryHelp(for: group))
                    }
                }
            }
        }
    }

    private var currencyForecasts: [CurrencyForecast] {
        analytics.currencyForecasts
    }

    private func currencyForecastIcons(for currency: CurrencyCode) -> some View {
        let items = analytics.forecastItems(for: currency)
        let visibleItems = Array(items.prefix(DashboardLayout.maximumCurrencyForecastIcons))
        let remainingCount = items.count - visibleItems.count
        return HStack(spacing: 6) {
            ForEach(visibleItems) { item in
                Button {
                    dismissForecastTooltip()
                    session.presentDetails(for: item.id)
                } label: {
                    ServiceIconView(
                        iconResourceName: item.iconResourceName,
                        iconURLString: item.iconURLString,
                        fallbackSeed: item.name,
                        size: DashboardLayout.currencyForecastIconSize
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    updateForecastTooltip(for: item.id, isHovering: isHovering)
                }
                .popover(
                    isPresented: forecastTooltipBinding(for: item.id),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)
                        Text(item.paymentSummary(style: currencyDisplayStyle))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(10)
                }
                .accessibilityLabel("查看 \(item.name) 的订阅详情")
                .accessibilityHint(item.paymentSummary(style: currencyDisplayStyle))
            }
            if remainingCount > 0 {
                Text("+\(remainingCount)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .accessibilityLabel("另有 \(remainingCount) 项订阅")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func forecastTooltipBinding(for itemID: UUID) -> Binding<Bool> {
        Binding(
            get: { forecastTooltipItemID == itemID },
            set: { isPresented in
                if !isPresented, forecastTooltipItemID == itemID {
                    forecastTooltipItemID = nil
                }
            }
        )
    }

    private func updateForecastTooltip(for itemID: UUID, isHovering: Bool) {
        forecastTooltipTask?.cancel()
        guard isHovering else {
            if forecastTooltipItemID == itemID {
                forecastTooltipItemID = nil
            }
            return
        }
        forecastTooltipTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            forecastTooltipItemID = itemID
        }
    }

    private func dismissForecastTooltip() {
        forecastTooltipTask?.cancel()
        forecastTooltipItemID = nil
    }

    private var displayedUpcomingItems: [SubscriptionListItem] {
        switch upcomingScope {
        case .active: session.dashboardActiveSubscriptionItems
        case .upcoming: session.dashboardUpcomingItems
        }
    }

    private var monthlyForecastText: String {
        guard let total = feature.exchangeRateQuote?.monthlyTotal(forecasts: currencyForecasts) else {
            return "—"
        }
        return String(
            format: AppLocalization.string("约 %@"),
            Money.display(total, currency: baseCurrency, style: currencyDisplayStyle)
        )
    }

    private var monthlyForecastHelp: String {
        feature.exchangeRateQuote?.disclosure
            ?? feature.exchangeRateError?.message
            ?? AppLocalization.string("暂无费用数据")
    }

    private var categoryForecastGroups: [CategoryForecastGroup] {
        analytics.categoryForecastGroups
    }

    private var categoryExchangeRateRequestID: String {
        let currencies = Set(analytics.categoryForecasts.map(\.currency))
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        return "\(session.exchangeRateRefreshRevision):\(baseCurrency.rawValue):\(currencies)"
    }

    private func categoryItems(for category: ServiceCategory) -> [SubscriptionListItem] {
        analytics.forecastItems.filter { $0.categoryValue == category }
    }

    private func categoryAmount(for group: CategoryForecastGroup) -> String {
        if group.forecasts.count == 1, let forecast = group.forecasts.first {
            return Money.display(
                forecast.annual,
                currency: forecast.currency,
                style: currencyDisplayStyle
            )
        }
        guard let total = feature.exchangeRateQuote?.annualTotal(forecasts: group.forecasts) else {
            return AppLocalization.string("约值暂不可用")
        }
        return String(
            format: AppLocalization.string("约 %@"),
            Money.display(total, currency: baseCurrency, style: currencyDisplayStyle)
        )
    }

    private func categoryHelp(for group: CategoryForecastGroup) -> String {
        guard group.forecasts.count > 1 else { return "展开查看原币种金额" }
        if let quote = feature.exchangeRateQuote {
            return "\(quote.disclosure) 展开后仍显示各订阅原币种金额。"
        }
        return feature.exchangeRateError?.message ?? "汇率暂不可用；展开后仍可查看原币种金额。"
    }

    @MainActor
    private func loadCategoryExchangeRates() async {
        await feature.loadExchangeRates(
            using: services.exchangeRates,
            forecasts: analytics.categoryForecasts,
            baseCurrency: baseCurrency,
            referenceDate: session.referenceDate
        )
    }
}

private enum DashboardLayout {
    static let maximumVisibleCurrencyForecasts = 4
    static let maximumCurrencyForecastIcons = 5
    static let currencyForecastIconSize: CGFloat = 24
    static let currencyForecastRowHeight: CGFloat = 60
    static let dividerHeight: CGFloat = 1
    static let scrollIndicatorGutter: CGFloat = 14

    static let primaryCardContentHeight =
        CGFloat(maximumVisibleCurrencyForecasts) * currencyForecastRowHeight
        + CGFloat(maximumVisibleCurrencyForecasts - 1) * dividerHeight
}

private extension View {
    func dashboardScrollIndicatorGutter() -> some View {
        contentMargins(
            .trailing,
            DashboardLayout.scrollIndicatorGutter,
            for: .scrollContent
        )
        .padding(.trailing, -DashboardLayout.scrollIndicatorGutter)
    }
}

private enum DashboardUpcomingScope: String, CaseIterable, Identifiable {
    case active
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: AppLocalization.string("正在订阅")
        case .upcoming: AppLocalization.string("即将到期")
        }
    }

    var emptyMessage: String {
        switch self {
        case .active: AppLocalization.string("暂无正在订阅项目")
        case .upcoming: AppLocalization.string("暂无到期项目")
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView(session: WindowSession())
    }
    .environment(AppServices(inMemory: true))
    .frame(width: 1000, height: 760)
}
