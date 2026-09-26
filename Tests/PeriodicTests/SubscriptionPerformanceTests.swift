import XCTest
@testable import Periodic

@MainActor
final class SubscriptionPerformanceTests: XCTestCase {
    func testThousandSubscriptionAnalyticsPerformance() {
        let referenceDate = LocalDate(dayNumber: 20_468)
        let items = makeListItems(referenceDate: referenceDate, count: 1_000)
        var classifiedCount = 0
        var renderedItemCount = 0

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            let analytics = SubscriptionAnalytics(
                items: items,
                referenceDate: referenceDate
            )
            classifiedCount = analytics.classifiedCount
            renderedItemCount = analytics.upcomingItems(within: 30).count
                + analytics.automaticRenewalDueItems.count
                + analytics.currencyForecasts.reduce(0) { $0 + $1.itemCount }
                + analytics.categoryForecasts.reduce(0) { $0 + $1.itemCount }
        }

        XCTAssertEqual(classifiedCount, items.count)
        XCTAssertGreaterThan(renderedItemCount, 0)
    }

    private func makeListItems(
        referenceDate: LocalDate,
        count: Int
    ) -> [SubscriptionListItem] {
        let offsets = [-365, -30, -7, -1, 0, 1, 7, 15, 30, 90, 365]
        let cycles = BillingCycle.allCases
        let currencies = CurrencyCode.allCases

        return (0..<count).map { index in
            let isLifetime = index.isMultiple(of: 19)
            let isUndated = !isLifetime && index.isMultiple(of: 13)
            let isInactive = index.isMultiple(of: 17)
            let cycle = cycles[index % cycles.count]
            let currency = currencies[index % currencies.count]
            let expiry = isLifetime || isUndated
                ? nil
                : LocalDate(
                    dayNumber: referenceDate.dayNumber + offsets[index % offsets.count]
                )
            let automaticallyRenews = !isLifetime
                && !isUndated
                && !isInactive
                && index.isMultiple(of: 11)

            return SubscriptionListItem(dto: SubscriptionDTO(
                id: UUID(),
                name: "Performance service \(index)",
                symbolName: "calendar",
                iconResourceName: nil,
                iconURLString: nil,
                category: ServiceCategory.allCases[index % ServiceCategory.allCases.count],
                managementState: isInactive ? .inactive : .active,
                billingKind: isLifetime ? .lifetime : .recurring,
                periodStart: expiry.map {
                    LocalDate(dayNumber: $0.dayNumber - cycle.rawValue * 30 + 1)
                },
                expiry: expiry,
                cycleMonths: isLifetime ? nil : cycle.rawValue,
                money: Money(
                    minorUnits: Int64((index % 97) + 1) * minorUnitFactor(for: currency),
                    currency: currency
                ),
                note: "",
                reminderEnabled: !isLifetime,
                automaticallyRenews: automaticallyRenews,
                revision: 1,
                createdAt: .distantPast,
                updatedAt: .distantPast
            ))
        }
    }

    private func minorUnitFactor(for currency: CurrencyCode) -> Int64 {
        (0..<currency.scale).reduce(Int64(1)) { result, _ in result * 10 }
    }
}
