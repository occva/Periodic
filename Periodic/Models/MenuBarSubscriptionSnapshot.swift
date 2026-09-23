import Foundation

struct MenuBarUpcomingItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let iconResourceName: String?
    let iconURLString: String?
    let expiry: LocalDate
    let remainingDays: Int
}

struct MenuBarSubscriptionSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let referenceDate: LocalDate
    let totalCount: Int
    let activeRecurringCount: Int
    let activeLifetimeCount: Int
    let expiredCount: Int
    let inactiveCount: Int
    let unknownDateCount: Int
    let dueTodayCount: Int
    let upcomingItems: [MenuBarUpcomingItem]
    let currencyForecasts: [CurrencyForecast]

    var activeCount: Int {
        activeRecurringCount + activeLifetimeCount
    }
}

enum MenuBarSnapshotBuilder {
    static func makeSnapshot(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate,
        generatedAt: Date = .now
    ) -> MenuBarSubscriptionSnapshot {
        let items = subscriptions.map(SubscriptionListItem.init(dto:))
        let analytics = SubscriptionAnalytics(items: items, referenceDate: referenceDate)
        let upcomingItems = analytics.upcomingItems(within: DueHorizon.thirtyDays.rawValue)
            .compactMap { item -> MenuBarUpcomingItem? in
                guard let expiry = item.expiry,
                      let remainingDays = item.remainingDayCount(relativeTo: referenceDate) else {
                    return nil
                }
                return MenuBarUpcomingItem(
                    id: item.id,
                    name: item.name,
                    iconResourceName: item.iconResourceName,
                    iconURLString: item.iconURLString,
                    expiry: expiry,
                    remainingDays: remainingDays
                )
            }

        return MenuBarSubscriptionSnapshot(
            generatedAt: generatedAt,
            referenceDate: referenceDate,
            totalCount: items.count,
            activeRecurringCount: analytics.effectiveRecurringCount,
            activeLifetimeCount: analytics.effectiveLifetimeCount,
            expiredCount: analytics.expiredCount,
            inactiveCount: analytics.inactiveCount,
            unknownDateCount: analytics.unknownDateCount,
            dueTodayCount: upcomingItems.count { $0.remainingDays == 0 },
            upcomingItems: upcomingItems,
            currencyForecasts: analytics.currencyForecasts
        )
    }
}
