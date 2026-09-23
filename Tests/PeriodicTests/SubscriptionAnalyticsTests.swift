import Foundation
import SwiftData
import Testing
@testable import Periodic

struct SubscriptionAnalyticsTests {
    private let anchor = LocalDate(dayNumber: 20_468) // 2026-01-15

    @Test func developmentDatasetCoversLargeAndVariedTimeline() {
        let inputs = DevelopmentSubscriptionDataset.make(referenceDate: anchor)

        #expect(inputs.count == 240)
        #expect(Set(inputs.map(\.id)).count == inputs.count)
        #expect(Set(inputs.map(\.name)).count == inputs.count)
        #expect(Set(inputs.map(\.category)) == Set(ServiceCategory.allCases))
        #expect(Set(inputs.map(\.money.currency)) == Set(CurrencyCode.allCases))
        #expect(Set(inputs.map(\.managementState)) == Set(ManagementState.allCases))
        #expect(Set(inputs.map(\.billingKind)) == Set(BillingKind.allCases))
        #expect(inputs.contains { $0.billingKind == .recurring && $0.expiry == nil })
        #expect(inputs.contains { $0.billingKind == .lifetime && $0.expiry == nil })

        let datedItems = inputs.compactMap(\.expiry)
        let earliest = datedItems.min()
        let latest = datedItems.max()
        #expect(earliest?.dayNumber == anchor.dayNumber - 1_095)
        #expect(latest?.dayNumber == anchor.dayNumber + 1_095)
    }

    @Test func largeDatasetRemainsConsistentAcrossMultipleReferenceDates() {
        let items = DevelopmentSubscriptionDataset.make(referenceDate: anchor)
            .map(makeListItem)
        let referenceDates = [-730, -365, 0, 365, 730].map {
            LocalDate(dayNumber: anchor.dayNumber + $0)
        }
        let snapshots = referenceDates.map {
            SubscriptionAnalytics(items: items, referenceDate: $0)
        }

        for snapshot in snapshots {
            #expect(snapshot.classifiedCount == items.count)
            #expect(snapshot.currencyForecasts.reduce(0) { $0 + $1.itemCount } == snapshot.forecastItems.count)
            #expect(snapshot.categoryForecasts.reduce(0) { $0 + $1.itemCount } == snapshot.forecastItems.count)

            let upcoming = snapshot.upcomingItems(within: 30)
            #expect(upcoming.allSatisfy {
                guard let days = $0.remainingDayCount(relativeTo: snapshot.referenceDate) else {
                    return false
                }
                return (0...30).contains(days)
            })
            #expect(zip(upcoming, upcoming.dropFirst()).allSatisfy { pair in
                let (earlier, later) = pair
                return (earlier.expiry ?? snapshot.referenceDate) <= (later.expiry ?? snapshot.referenceDate)
            })
        }

        #expect(isNondecreasing(snapshots.map(\.expiredCount)))
        #expect(isNonincreasing(snapshots.map(\.effectiveRecurringCount)))
        #expect(Set(snapshots.map(\.inactiveCount)).count == 1)
        #expect(Set(snapshots.map(\.effectiveLifetimeCount)).count == 1)
        #expect(Set(snapshots.map(\.unknownDateCount)).count == 1)
    }

    @Test func dueBoundariesAreCorrectAtSeveralPointsInTime() {
        let offsets = [-31, -30, -8, -7, -1, 0, 1, 7, 8, 15, 30, 31]
        let items = offsets.map { offset in
            makeListItem(
                makeInput(
                    name: "偏移 \(offset)",
                    expiry: LocalDate(dayNumber: anchor.dayNumber + offset)
                )
            )
        }

        let atAnchor = SubscriptionAnalytics(items: items, referenceDate: anchor)
        #expect(atAnchor.expiredCount == 5)
        #expect(atAnchor.effectiveRecurringCount == 7)
        #expect(atAnchor.upcomingItems(within: 7).count == 3)
        #expect(atAnchor.upcomingItems(within: 15).count == 5)
        #expect(atAnchor.upcomingItems(within: 30).count == 6)

        let thirtyDaysEarlier = SubscriptionAnalytics(
            items: items,
            referenceDate: LocalDate(dayNumber: anchor.dayNumber - 30)
        )
        #expect(thirtyDaysEarlier.expiredCount == 1)
        #expect(thirtyDaysEarlier.upcomingItems(within: 30).count == 5)

        let sevenDaysLater = SubscriptionAnalytics(
            items: items,
            referenceDate: LocalDate(dayNumber: anchor.dayNumber + 7)
        )
        #expect(sevenDaysLater.expiredCount == 7)
        #expect(sevenDaysLater.upcomingItems(within: 30).count == 5)
    }

    @MainActor
    @Test func bulkDatasetPersistsInOneStoreOperation() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let store = SubscriptionStore(modelContainer: container)
        let inputs = DevelopmentSubscriptionDataset.make(referenceDate: anchor)

        try await store.create(inputs)
        let records = try await store.fetchAll()

        #expect(records.count == inputs.count)
        #expect(Set(records.map(\.id)) == Set(inputs.map(\.id)))
        #expect(Set(records.map(\.money.currency)) == Set(CurrencyCode.allCases))
        #expect(records.compactMap(\.expiry).min()?.dayNumber == anchor.dayNumber - 1_095)
        #expect(records.compactMap(\.expiry).max()?.dayNumber == anchor.dayNumber + 1_095)
    }

    @Test func expiredSubscriptionUsesDerivedExpiredStatusAndZeroProgress() {
        let expiry = LocalDate(dayNumber: anchor.dayNumber - 1)
        let item = makeListItem(makeInput(name: "已过期服务", expiry: expiry))

        #expect(item.managementState == .active)
        #expect(item.managementStatus(relativeTo: anchor) == "已过期")
        #expect(item.remainingProgress(relativeTo: anchor) == 0)
    }

    @Test func tableProgressUsesAbsoluteRemainingDaysOnHundredDayScale() {
        let oneHundredOneDays = makeListItem(
            makeInput(
                name: "剩余一百零一天",
                expiry: LocalDate(dayNumber: anchor.dayNumber + 101)
            )
        )
        let ninetyNineDays = makeListItem(
            makeInput(
                name: "剩余九十九天",
                expiry: LocalDate(dayNumber: anchor.dayNumber + 99)
            )
        )
        let thirtyDays = makeListItem(
            makeInput(
                name: "剩余三十天",
                expiry: LocalDate(dayNumber: anchor.dayNumber + 30)
            )
        )
        let expired = makeListItem(
            makeInput(
                name: "已过期",
                expiry: LocalDate(dayNumber: anchor.dayNumber - 1)
            )
        )

        #expect(oneHundredOneDays.remainingDaysProgress(relativeTo: anchor) == 1)
        #expect(ninetyNineDays.remainingDaysProgress(relativeTo: anchor) == 0.99)
        #expect(thirtyDays.remainingDaysProgress(relativeTo: anchor) == 0.3)
        #expect(expired.remainingDaysProgress(relativeTo: anchor) == 0)
    }

    @MainActor
    @Test func tableDefaultsToRemainingDaysFromPositiveToNegative() async throws {
        let services = AppServices(inMemory: true)
        let store = try #require(services.subscriptionStore)
        let today = LocalDate.today
        let inputs = [
            makeInput(name: "负数", expiry: LocalDate(dayNumber: today.dayNumber - 5)),
            makeInput(name: "最大正数", expiry: LocalDate(dayNumber: today.dayNumber + 30)),
            makeInput(name: "零", expiry: today),
            makeInput(name: "较小正数", expiry: LocalDate(dayNumber: today.dayNumber + 7)),
        ]
        try await store.create(inputs)

        let session = WindowSession(referenceDate: today)
        await session.reload(using: services)

        #expect(session.filteredItems.map(\.remainingDayCount) == [30, 7, 0, -5])
    }

    @MainActor
    @Test func overviewFiltersComposeAndCanBeCleared() async throws {
        let services = AppServices(inMemory: true)
        let store = try #require(services.subscriptionStore)
        let inputs = DevelopmentSubscriptionDataset.make(referenceDate: anchor, count: 80)
        try await store.create(inputs)

        let session = WindowSession(referenceDate: anchor)
        await session.reload(using: services)

        session.overviewCurrency = .usd
        #expect(!session.filteredItems.isEmpty)
        #expect(session.filteredItems.allSatisfy { $0.money.currency == .usd })

        session.overviewCategory = .tools
        #expect(session.filteredItems.allSatisfy {
            $0.money.currency == .usd && $0.categoryValue == .tools
        })
        #expect(session.hasOverviewFilters)

        session.clearOverviewFilters()
        #expect(!session.hasOverviewFilters)
        #expect(session.filteredItems.count == inputs.count)
    }

    @MainActor
    @Test func appDataVersionsNotifyEveryOpenWindow() {
        let services = AppServices(inMemory: true)
        let initialSubscriptionVersion = services.subscriptionDataVersion
        let initialTemplateVersion = services.templateDataVersion

        services.notifySubscriptionDataChanged()
        services.notifyTemplateDataChanged()

        #expect(services.subscriptionDataVersion == initialSubscriptionVersion + 1)
        #expect(services.templateDataVersion == initialTemplateVersion + 1)
    }

    @MainActor
    @Test func developmentDatasetContainsMultipleSubscriptionOccurrences() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let store = SubscriptionStore(modelContainer: container)
        let inputs = DevelopmentSubscriptionDataset.make(referenceDate: anchor, count: 20)
        let historicalPeriods = DevelopmentSubscriptionDataset.makeHistoricalPeriods(for: inputs)

        try await store.create(inputs, additionalPeriods: historicalPeriods)

        let subscriptionWithHistory = try #require(
            inputs.enumerated().first { pair in
                pair.offset % 5 == 4
                    && pair.element.periodStart != nil
                    && pair.element.expiry != nil
            }?.element
        )
        let periods = try await store.fetchPeriods(for: subscriptionWithHistory.id)
        #expect(periods.count == 5)
        #expect(periods.map(\.start) == periods.map(\.start).sorted())
    }

    private func makeInput(name: String, expiry: LocalDate) -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: UUID(),
            name: name,
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: LocalDate(dayNumber: expiry.dayNumber - 29),
            expiry: expiry,
            cycleMonths: 1,
            money: Money(minorUnits: 1_000, currency: .cny),
            note: "",
            reminderEnabled: true
        )
    }

    private func makeListItem(_ input: SubscriptionCreateInput) -> SubscriptionListItem {
        SubscriptionListItem(
            dto: SubscriptionDTO(
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
                revision: 1,
                createdAt: .distantPast,
                updatedAt: .distantPast
            )
        )
    }

    private func isNondecreasing(_ values: [Int]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { pair in
            let (earlier, later) = pair
            return earlier <= later
        }
    }

    private func isNonincreasing(_ values: [Int]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { pair in
            let (earlier, later) = pair
            return earlier >= later
        }
    }
}
