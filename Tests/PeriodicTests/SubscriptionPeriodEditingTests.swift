import Foundation
import SwiftData
import Testing
@testable import Periodic

struct SubscriptionPeriodEditingTests {
    @MainActor
    @Test func manuallyAddingHistoryKeepsCurrentSubscriptionValuesUnchanged() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let store = SubscriptionStore(modelContainer: container)
        let subscription = SubscriptionCreateInput(
            id: UUID(),
            name: "可补录周期",
            symbolName: "calendar.badge.plus",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: nil,
            expiry: nil,
            cycleMonths: 1,
            money: Money(minorUnits: 8_100, currency: .cny),
            note: "",
            reminderEnabled: true
        )
        _ = try await store.create(subscription)
        #expect(try await store.fetchPeriods(for: subscription.id).isEmpty)

        let start = LocalDate(dayNumber: 21_000)
        let end = LocalDate(dayNumber: start.dayNumber + 89)
        let period = SubscriptionPeriodCreateInput(
            id: UUID(),
            subscriptionID: subscription.id,
            billingKind: .recurring,
            cycleMonths: 3,
            start: start,
            end: end,
            money: Money(minorUnits: 5_400, currency: .usd)
        )

        try await store.addPeriod(
            SubscriptionPeriodAddInput(
                period: period,
                expectedSubscriptionRevision: 1
            )
        )

        let storedPeriod = try #require(try await store.fetchPeriods(for: subscription.id).first)
        #expect(storedPeriod.id == period.id)
        #expect(storedPeriod.start == start)
        #expect(storedPeriod.end == end)
        #expect(storedPeriod.cycleMonths == 3)
        #expect(storedPeriod.money == Money(minorUnits: 5_400, currency: .usd))

        let currentSubscription = try #require(try await store.fetchAll().first)
        #expect(currentSubscription.periodStart == nil)
        #expect(currentSubscription.expiry == nil)
        #expect(currentSubscription.cycleMonths == 1)
        #expect(currentSubscription.money == Money(minorUnits: 8_100, currency: .cny))
        #expect(currentSubscription.revision == 2)

        let stalePeriod = SubscriptionPeriodCreateInput(
            id: UUID(),
            subscriptionID: subscription.id,
            billingKind: .recurring,
            cycleMonths: 1,
            start: end,
            end: LocalDate(dayNumber: end.dayNumber + 29),
            money: subscription.money
        )
        do {
            try await store.addPeriod(
                SubscriptionPeriodAddInput(
                    period: stalePeriod,
                    expectedSubscriptionRevision: 1
                )
            )
            Issue.record("使用旧版本新增周期记录应失败。")
        } catch SubscriptionStore.StoreError.revisionConflict {
            // Expected: the first addition incremented the parent subscription revision.
        }
        #expect(try await store.fetchPeriods(for: subscription.id).count == 1)
    }

    @MainActor
    @Test func editingHistoryKeepsCurrentSubscriptionValuesUnchanged() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let store = SubscriptionStore(modelContainer: container)
        let start = LocalDate(dayNumber: 21_000)
        let expiry = LocalDate(dayNumber: start.dayNumber + 29)
        let subscription = SubscriptionCreateInput(
            id: UUID(),
            name: "可编辑周期",
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: start,
            expiry: expiry,
            cycleMonths: 1,
            money: Money(minorUnits: 8_100, currency: .cny),
            note: "",
            reminderEnabled: true
        )
        _ = try await store.create(subscription)

        let originalPeriods = try await store.fetchPeriods(for: subscription.id)
        let originalPeriod = try #require(originalPeriods.first)
        let editedStart = LocalDate(dayNumber: start.dayNumber - 1)
        let editedEnd = LocalDate(dayNumber: expiry.dayNumber + 1)
        let update = SubscriptionPeriodUpdateInput(
            original: originalPeriod,
            expectedSubscriptionRevision: 1,
            billingKind: .recurring,
            cycleMonths: 3,
            start: editedStart,
            end: editedEnd,
            money: Money(minorUnits: 12_300, currency: .usd)
        )

        try await store.updatePeriod(update)

        let editedPeriods = try await store.fetchPeriods(for: subscription.id)
        let editedPeriod = try #require(editedPeriods.first)
        #expect(editedPeriod.start == editedStart)
        #expect(editedPeriod.end == editedEnd)
        #expect(editedPeriod.cycleMonths == 3)
        #expect(editedPeriod.money == Money(minorUnits: 12_300, currency: .usd))

        let currentSubscription = try #require(try await store.fetchAll().first)
        #expect(currentSubscription.periodStart == start)
        #expect(currentSubscription.expiry == expiry)
        #expect(currentSubscription.cycleMonths == 1)
        #expect(currentSubscription.money == Money(minorUnits: 8_100, currency: .cny))
        #expect(currentSubscription.revision == 2)

        do {
            try await store.updatePeriod(update)
            Issue.record("使用旧版本再次保存周期记录应失败。")
        } catch SubscriptionStore.StoreError.revisionConflict {
            // Expected: the first edit incremented the parent subscription revision.
        }
    }
}
