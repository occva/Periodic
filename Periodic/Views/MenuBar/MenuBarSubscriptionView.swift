import SwiftUI

struct MenuBarSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @AppStorage(PreferenceKey.menuBarDueHorizon) private var dueHorizonRaw =
        MenuBarPreferences.defaultDueHorizon.rawValue
    @AppStorage(PreferenceKey.menuBarShowsForecasts) private var showsForecasts = true
    @AppStorage(PreferenceKey.exchangeRateBaseCurrency) private var baseCurrency = CurrencyCode.cny
    @State private var contentHeight: CGFloat = 180

    let feature: MenuBarFeature
    let services: AppServices
    let windowRouter: AppWindowRouter

    private var dueHorizon: DueHorizon {
        MenuBarPreferences.dueHorizon(for: dueHorizonRaw)
    }

    private var upcomingItemsInSelectedRange: [MenuBarUpcomingItem] {
        feature.snapshot?.upcomingItems
            .filter { $0.remainingDays <= dueHorizon.rawValue }
            ?? []
    }

    private var visibleUpcomingItems: [MenuBarUpcomingItem] {
        upcomingItemsInSelectedRange.prefix(5).map { $0 }
    }

    var body: some View {
        ScrollView {
            menuContent
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { newHeight in
                    guard newHeight > 0 else { return }
                    contentHeight = newHeight
                }
        }
        .frame(width: 320, height: min(contentHeight, 560))
        .accessibilityIdentifier("menu-bar-subscription-view")
        .onAppear {
            dueHorizonRaw = MenuBarPreferences.normalizedDueHorizonRawValue(dueHorizonRaw)
        }
        .task {
            await feature.reload(
                using: services,
                targetCurrency: baseCurrency,
                shouldLoadExchangeRates: showsForecasts
            )
        }
        .onChange(of: baseCurrency) { _, _ in
            reload()
        }
        .onChange(of: showsForecasts) { _, _ in
            reload()
        }
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if feature.isLoading, feature.snapshot == nil {
            HStack {
                Spacer()
                ProgressView("正在读取订阅…")
                Spacer()
            }
            .frame(minHeight: 160)
        } else if let snapshot = feature.snapshot {
            if let loadError = feature.loadError {
                staleSnapshotBanner(loadError)
            }
            if snapshot.totalCount == 0 {
                emptyState
            } else {
                overview(snapshot)
                upcomingSection
                if !snapshot.currencyForecasts.isEmpty {
                    if showsForecasts {
                        forecastSection(snapshot)
                    } else {
                        hiddenForecastSection
                    }
                }
            }
        } else {
            errorState
        }
    }

    private func overview(_ snapshot: MenuBarSubscriptionSnapshot) -> some View {
        Button {
            openMainWindow(.dashboard(dueHorizon: nil))
        } label: {
            HStack {
                Text("\(snapshot.activeCount) 个有效订阅")
                    .font(.headline.monospacedDigit())
                Spacer()
                if feature.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在更新")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开 Periodic")
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("即将到期")
                    .font(.headline)
                if !upcomingItemsInSelectedRange.isEmpty {
                    Text("\(upcomingItemsInSelectedRange.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(dueHorizon.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if visibleUpcomingItems.isEmpty {
                Text("所选范围内没有到期项目")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .center)
            } else {
                VStack(spacing: 2) {
                    ForEach(visibleUpcomingItems) { item in
                        upcomingButton(item)
                    }
                }
            }

            Button {
                openMainWindow(.overview)
            } label: {
                HStack(spacing: 4) {
                    Text("查看全部服务")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .accessibilityHint("打开表格视图")
        }
    }

    private func upcomingButton(_ item: MenuBarUpcomingItem) -> some View {
        Button {
            openMainWindow(.subscriptionDetails(item.id))
        } label: {
            HStack(spacing: 8) {
                ServiceIconView(
                    iconResourceName: item.iconResourceName,
                    iconURLString: item.iconURLString,
                    fallbackSeed: item.name,
                    size: 24
                )
                Text(item.name)
                    .lineLimit(1)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(relativeExpiryText(item.remainingDays))
                        .fontWeight(item.remainingDays <= 7 ? .medium : .regular)
                    Text(item.expiry.displayText)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel(
            "\(item.name)，\(item.expiry.displayText)，\(relativeExpiryText(item.remainingDays))"
        )
        .accessibilityHint("打开订阅详情")
    }

    private func forecastSection(_ snapshot: MenuBarSubscriptionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("月均")
                .font(.headline)

            ForEach(snapshot.currencyForecasts) { forecast in
                HStack(alignment: .firstTextBaseline) {
                    Text(currencyDisplayStyle.label(for: forecast.currency))
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(Money.displayNumber(forecast.monthly, currency: forecast.currency))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }

            exchangeRateSummary(snapshot)
        }
    }

    private var hiddenForecastSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("月均")
                .font(.headline)
            Text("金额已隐藏")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func exchangeRateSummary(_ snapshot: MenuBarSubscriptionSnapshot) -> some View {
        if let quote = feature.exchangeRateQuote,
           let total = quote.monthlyTotal(forecasts: snapshot.currencyForecasts) {
            Text(
                String(
                    format: AppLocalization.string("本月花费约 %@"),
                    Money.display(
                        total,
                        currency: quote.baseCurrency,
                        style: currencyDisplayStyle
                    )
                )
            )
            .help(quote.disclosure)
        } else if feature.isLoading {
            Text("正在更新汇率…")
        } else if feature.exchangeRateError != nil {
            Text("汇率暂不可用")
                .help(feature.exchangeRateError?.message ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有订阅", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("新建订阅，或从内置模板快速开始。")
        } actions: {
            HStack {
                Button("新建订阅") {
                    openMainWindow(.newSubscription)
                }
                Button("打开模板库") {
                    openMainWindow(.templateLibrary)
                }
            }
        }
        .frame(minHeight: 180)
    }

    private var errorState: some View {
        ContentUnavailableView {
            Label("订阅信息暂不可用", systemImage: "exclamationmark.triangle")
        } description: {
            Text(feature.loadError?.message ?? "请打开 Periodic 查看详情。")
        } actions: {
            Button("重试") {
                reload()
            }
            Button("打开 Periodic") {
                openMainWindow(.dashboard(dueHorizon: nil))
            }
        }
        .frame(minHeight: 180)
    }

    private func staleSnapshotBanner(_ error: PresentedError) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("更新失败，正在显示上次结果")
                Text(error.message)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func relativeExpiryText(_ remainingDays: Int) -> String {
        guard remainingDays != 0 else { return AppLocalization.string("今天到期") }
        return String(
            format: AppLocalization.string("%d 天后"),
            remainingDays
        )
    }

    private func openMainWindow(_ route: MainWindowRoute) {
        dismiss()
        guard !windowRouter.request(route) else { return }
        windowRouter.activateApplication()
        openWindow(id: AppConfiguration.mainWindowID)
    }

    private func reload() {
        Task { @MainActor in
            await feature.reload(
                using: services,
                targetCurrency: baseCurrency,
                shouldLoadExchangeRates: showsForecasts
            )
        }
    }
}
