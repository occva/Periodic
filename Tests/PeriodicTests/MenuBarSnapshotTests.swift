import Foundation
import Testing
@testable import Periodic

struct MenuBarSnapshotTests {
    private let anchor = LocalDate(dayNumber: 20_468) // 2026-01-15

    @Test func snapshotUsesSharedStatusAndDueDateRules() {
        let subscriptions = [
            makeSubscription(name: "今天", expiryOffset: 0, currency: .cny),
            makeSubscription(name: "七天", expiryOffset: 7, currency: .usd),
            makeSubscription(name: "八天", expiryOffset: 8, currency: .cny),
            makeSubscription(name: "三十天", expiryOffset: 30, currency: .cny),
            makeSubscription(name: "三十一天", expiryOffset: 31, currency: .usd),
            makeSubscription(name: "过期", expiryOffset: -1, currency: .cny),
            makeSubscription(
                name: "停用",
                expiryOffset: 3,
                currency: .cny,
                managementState: .inactive
            ),
            makeSubscription(
                name: "终生",
                expiryOffset: nil,
                currency: .cny,
                billingKind: .lifetime
            ),
            makeSubscription(name: "日期未知", expiryOffset: nil, currency: .cny),
        ]

        let snapshot = MenuBarSnapshotBuilder.makeSnapshot(
            subscriptions: subscriptions,
            referenceDate: anchor,
            generatedAt: Date(timeIntervalSince1970: 10)
        )

        #expect(snapshot.totalCount == 9)
        #expect(snapshot.activeRecurringCount == 5)
        #expect(snapshot.activeLifetimeCount == 1)
        #expect(snapshot.expiredCount == 1)
        #expect(snapshot.inactiveCount == 1)
        #expect(snapshot.unknownDateCount == 1)
        #expect(snapshot.dueTodayCount == 1)
        #expect(snapshot.upcomingItems.map(\.name) == ["今天", "七天", "八天", "三十天"])
        #expect(snapshot.upcomingItems.map(\.remainingDays) == [0, 7, 8, 30])
        #expect(Set(snapshot.currencyForecasts.map(\.currency)) == [.cny, .usd])
        #expect(snapshot.currencyForecasts.reduce(0) { $0 + $1.itemCount } == 5)
    }

    @Test func dueHorizonFallsBackForUnknownStoredValue() {
        #expect(MenuBarPreferences.dueHorizon(for: 7) == .sevenDays)
        #expect(MenuBarPreferences.dueHorizon(for: 15) == .fifteenDays)
        #expect(MenuBarPreferences.dueHorizon(for: 999) == .fifteenDays)
        #expect(MenuBarPreferences.normalizedDueHorizonRawValue(30) == 30)
        #expect(MenuBarPreferences.normalizedDueHorizonRawValue(999) == 15)
    }

    @Test func exchangeRateQuoteKeepsCurrencyRowsSeparateAndBuildsApproximateTotal() {
        let forecasts = [
            CurrencyForecast(currency: .cny, monthly: 141, annual: 1_692, itemCount: 2),
            CurrencyForecast(currency: .usd, monthly: 42, annual: 504, itemCount: 1),
        ]

        let quote = ExchangeRateQuote(
            baseCurrency: .cny,
            date: "2026-09-23",
            ratesPerBaseUnit: [.cny: 1, .usd: Decimal(14) / Decimal(100)],
            isStale: false,
            source: .frankfurter
        )
        let total = quote.monthlyTotal(forecasts: forecasts)

        #expect(total == 441)
        #expect(forecasts.map(\.currency) == [.cny, .usd])
    }

    @Test func exchangeRateQuoteRejectsIncompleteConversion() {
        let quote = ExchangeRateQuote(
            baseCurrency: .cny,
            date: "2026-09-23",
            ratesPerBaseUnit: [.cny: 1],
            isStale: false,
            source: .frankfurter
        )
        let forecasts = [
            CurrencyForecast(currency: .usd, monthly: 10, annual: 120, itemCount: 1),
        ]

        #expect(quote.monthlyTotal(forecasts: forecasts) == nil)
    }

    @MainActor
    @Test func featureLoadsSnapshotFromSharedStore() async throws {
        let services = AppServices(inMemory: true)
        let store = try #require(services.subscriptionStore)
        _ = try await store.create(makeInput(name: "菜单栏测试", expiryOffset: 0, currency: .cny))

        let feature = MenuBarFeature()
        await feature.reload(using: services, referenceDate: anchor)

        #expect(feature.loadError == nil)
        #expect(feature.snapshot?.totalCount == 1)
        #expect(feature.snapshot?.dueTodayCount == 1)
        #expect(feature.statusItemAccessibilityLabel.contains("1"))
    }

    private func makeSubscription(
        name: String,
        expiryOffset: Int?,
        currency: CurrencyCode,
        managementState: ManagementState = .active,
        billingKind: BillingKind = .recurring
    ) -> SubscriptionDTO {
        let input = makeInput(
            name: name,
            expiryOffset: expiryOffset,
            currency: currency,
            managementState: managementState,
            billingKind: billingKind
        )
        return SubscriptionDTO(
            id: input.id,
            name: input.name,
            symbolName: input.symbolName,
            iconResourceName: input.iconResourceName,
            iconURLString: input.iconURLString,
            category: input.category,
            managementState: input.managementState,
            billingKind: input.billingKind,
            periodStart: input.periodStart,
            expiry: input.expiry,
            cycleMonths: input.cycleMonths,
            money: input.money,
            note: input.note,
            reminderEnabled: input.reminderEnabled,
            revision: 0,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeInput(
        name: String,
        expiryOffset: Int?,
        currency: CurrencyCode,
        managementState: ManagementState = .active,
        billingKind: BillingKind = .recurring
    ) -> SubscriptionCreateInput {
        let expiry = expiryOffset.map { LocalDate(dayNumber: anchor.dayNumber + $0) }
        return SubscriptionCreateInput(
            id: UUID(),
            name: name,
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: managementState,
            billingKind: billingKind,
            periodStart: billingKind == .lifetime
                ? anchor
                : expiry.map { LocalDate(dayNumber: $0.dayNumber - 29) },
            expiry: billingKind == .lifetime ? nil : expiry,
            cycleMonths: billingKind == .lifetime ? nil : 1,
            money: Money(minorUnits: 1_000, currency: currency),
            note: "",
            reminderEnabled: billingKind == .recurring
        )
    }
}
