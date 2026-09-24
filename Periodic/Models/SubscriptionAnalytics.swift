import Foundation

enum SubscriptionStatusBucket: CaseIterable, Sendable {
    case effectiveRecurring
    case effectiveLifetime
    case expired
    case inactive
    case unknownDate
}

struct CurrencyForecast: Identifiable, Equatable, Sendable {
    var id: CurrencyCode { currency }

    let currency: CurrencyCode
    let monthly: Decimal
    let annual: Decimal
    let itemCount: Int
}

struct CategoryForecast: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let category: ServiceCategory
        let currency: CurrencyCode
    }

    var id: ID { ID(category: category, currency: currency) }

    let category: ServiceCategory
    let currency: CurrencyCode
    let annual: Decimal
    let itemCount: Int
}

struct CategoryForecastGroup: Identifiable, Equatable, Sendable {
    var id: ServiceCategory { category }

    let category: ServiceCategory
    let forecasts: [CategoryForecast]
}

/// A deterministic view of subscription state at one local calendar date.
/// Keeping the reference date explicit makes midnight and historical/future
/// scenarios testable without changing the system clock.
struct SubscriptionAnalytics: Sendable {
    let items: [SubscriptionListItem]
    let referenceDate: LocalDate

    func status(of item: SubscriptionListItem) -> SubscriptionStatusBucket {
        guard item.managementState == .active else { return .inactive }
        guard item.billingKindValue == .recurring else { return .effectiveLifetime }
        guard let expiry = item.expiry else { return .unknownDate }
        return expiry < referenceDate ? .expired : .effectiveRecurring
    }

    func count(for bucket: SubscriptionStatusBucket) -> Int {
        items.count { status(of: $0) == bucket }
    }

    var effectiveRecurringCount: Int { count(for: .effectiveRecurring) }
    var effectiveLifetimeCount: Int { count(for: .effectiveLifetime) }
    var expiredCount: Int { count(for: .expired) }
    var inactiveCount: Int { count(for: .inactive) }
    var unknownDateCount: Int { count(for: .unknownDate) }

    var classifiedCount: Int {
        SubscriptionStatusBucket.allCases.reduce(0) { $0 + count(for: $1) }
    }

    var forecastItems: [SubscriptionListItem] {
        items.filter {
            status(of: $0) == .effectiveRecurring && ($0.cycleMonths ?? 0) > 0
        }
    }

    func upcomingItems(within dayCount: Int) -> [SubscriptionListItem] {
        items
            .filter {
                guard status(of: $0) == .effectiveRecurring,
                      let remainingDays = $0.remainingDayCount(relativeTo: referenceDate) else {
                    return false
                }
                return (0...dayCount).contains(remainingDays)
            }
            .sorted(by: expiryAscending)
    }

    var currencyForecasts: [CurrencyForecast] {
        Dictionary(grouping: forecastItems, by: \.money.currency)
            .map { currency, groupedItems in
                CurrencyForecast(
                    currency: currency,
                    monthly: groupedItems.reduce(Decimal.zero) {
                        $0 + $1.money.monthlyAmount(cycleMonths: $1.cycleMonths ?? 1)
                    },
                    annual: groupedItems.reduce(Decimal.zero) {
                        $0 + $1.money.annualAmount(cycleMonths: $1.cycleMonths ?? 1)
                    },
                    itemCount: groupedItems.count
                )
            }
            .sorted { $0.currency.rawValue < $1.currency.rawValue }
    }

    var categoryForecasts: [CategoryForecast] {
        Dictionary(grouping: forecastItems) {
            CategoryForecast.ID(category: $0.categoryValue, currency: $0.money.currency)
        }
        .map { key, groupedItems in
            CategoryForecast(
                category: key.category,
                currency: key.currency,
                annual: groupedItems.reduce(Decimal.zero) {
                    $0 + $1.money.annualAmount(cycleMonths: $1.cycleMonths ?? 1)
                },
                itemCount: groupedItems.count
            )
        }
        .sorted {
            if $0.category != $1.category {
                return $0.category.title.localizedStandardCompare($1.category.title) == .orderedAscending
            }
            return $0.currency.rawValue < $1.currency.rawValue
        }
    }

    var categoryForecastGroups: [CategoryForecastGroup] {
        Dictionary(grouping: categoryForecasts, by: \.category)
            .map { category, forecasts in
                CategoryForecastGroup(category: category, forecasts: forecasts)
            }
            .sorted {
                $0.category.title.localizedStandardCompare($1.category.title) == .orderedAscending
            }
    }

    private func expiryAscending(_ lhs: SubscriptionListItem, _ rhs: SubscriptionListItem) -> Bool {
        switch (lhs.expiry, rhs.expiry) {
        case let (left?, right?):
            if left != right { return left < right }
            if lhs.name != rhs.name {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil):
            if lhs.name != rhs.name {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
