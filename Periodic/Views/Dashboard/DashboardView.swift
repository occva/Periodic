import SwiftUI

struct DashboardView: View {
    @Bindable var session: WindowSession
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @State private var expandedCategoryForecasts = Set<CategoryForecast.ID>()

    private var analytics: SubscriptionAnalytics { session.analytics }

    var body: some View {
        ScrollView {
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
        }
        .accessibilityIdentifier("dashboard-page")
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("概况").font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                SummaryMetricCard(title: "全库总数", value: "\(session.items.count)", symbol: "rectangle.stack")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dashboard-total-count")
                SummaryMetricCard(
                    title: "当前有效",
                    value: "\(analytics.effectiveRecurringCount + analytics.effectiveLifetimeCount)",
                    detail: "周期 \(analytics.effectiveRecurringCount) · 终生 \(analytics.effectiveLifetimeCount)",
                    symbol: "checkmark.circle"
                )
                SummaryMetricCard(title: "已过期", value: "\(analytics.expiredCount)", symbol: "exclamationmark.circle")
                SummaryMetricCard(title: "已停用", value: "\(analytics.inactiveCount)", symbol: "pause.circle")
                SummaryMetricCard(title: "日期未知", value: "\(analytics.unknownDateCount)", symbol: "questionmark.circle")
            }
        }
    }

    private var forecastCard: some View {
        DashboardCard(title: "预估费用", symbol: "banknote") {
            if currencyForecasts.isEmpty {
                Text("暂无费用数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(currencyForecasts) { forecast in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(currencyDisplayStyle.label(for: forecast.currency))
                                .font(.headline)
                            Spacer()
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
                        .padding(.vertical, 8)
                        if forecast.id != currencyForecasts.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var upcomingCard: some View {
        DashboardCard(title: "即将到期", symbol: "clock") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("临期范围", selection: $session.dueHorizon) {
                    ForEach(DueHorizon.allCases) { horizon in
                        Text(horizon.title).tag(horizon)
                    }
                }
                .pickerStyle(.segmented)
                Text("共 \(session.dashboardUpcomingItems.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if session.dashboardUpcomingItems.isEmpty {
                    Text("暂无到期项目")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(session.dashboardUpcomingItems) { item in
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
                    .frame(maxHeight: 150)
                }
            }
        }
    }

    private var categoryCard: some View {
        DashboardCard(title: "服务类型年化", symbol: "chart.bar.xaxis") {
            if categoryForecasts.isEmpty {
                Text("暂无费用数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                IndependentColumnLayout(minimumColumnWidth: 220, spacing: 12) {
                    ForEach(categoryForecasts) { forecast in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedCategoryForecasts.contains(forecast.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedCategoryForecasts.insert(forecast.id)
                                    } else {
                                        expandedCategoryForecasts.remove(forecast.id)
                                    }
                                }
                            )
                        ) {
                            VStack(spacing: 6) {
                                ForEach(categoryItems(for: forecast)) { item in
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
                                Text(forecast.category.title)
                                Spacer()
                                Text(
                                    Money.display(
                                        forecast.annual,
                                        currency: forecast.currency,
                                        style: currencyDisplayStyle
                                    )
                                )
                                    .monospacedDigit()
                            }
                        }
                        .padding(10)
                    }
                }
            }
        }
    }

    private var currencyForecasts: [CurrencyForecast] {
        analytics.currencyForecasts
    }

    private var categoryForecasts: [CategoryForecast] {
        analytics.categoryForecasts
    }

    private func categoryItems(for forecast: CategoryForecast) -> [SubscriptionListItem] {
        analytics.forecastItems.filter {
            $0.categoryValue == forecast.category && $0.money.currency == forecast.currency
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView(session: WindowSession())
    }
    .frame(width: 1000, height: 760)
}
