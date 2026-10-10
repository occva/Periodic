import Foundation
import SwiftData
import Testing
@testable import Periodic

@MainActor
struct WindowSessionTests {
    @Test func deletedTargetClosesDetailsAndKeepsEditorIdentity() async throws {
        let services = AppServices(inMemory: true)
        let store = try #require(services.subscriptionStore)
        let input = makeInput(name: "Original", state: .active, expiry: nil)
        _ = try await store.create(input)
        let session = WindowSession()
        await session.reload(using: services)
        session.presentDetails(for: input.id)
        session.presentEditor(for: input.id)
        let preview = try await store.previewDeletion([
            SubscriptionMutationTarget(id: input.id, expectedRevision: 1),
        ])
        _ = try await store.delete(preview)
        await session.reload(using: services)
        #expect(!session.isPresentingSubscriptionDetail)
        #expect(session.detailSubscriptionID == nil)
        #expect(session.isPresentingSubscriptionEditor)
        #expect(session.editingSubscription?.id == input.id)
        #expect(session.editingSubscription?.revision == 1)
        await #expect(throws: SubscriptionStore.StoreError.notFound) {
            try await store.update(input, expectedRevision: 1, historyPolicy: .currentOnly)
        }
        #expect(try await store.fetchAll().isEmpty)
    }

    @Test func reloadDoesNotAdvanceAnOpenDraftRevision() async throws {
        let services = AppServices(inMemory: true)
        let store = try #require(services.subscriptionStore)
        let input = makeInput(name: "Original", state: .active, expiry: nil)
        _ = try await store.create(input)
        let session = WindowSession()
        await session.reload(using: services)
        session.presentEditor(for: input.id)
        try await store.setManagementState(.inactive, for: [
            SubscriptionMutationTarget(id: input.id, expectedRevision: 1),
        ])
        await session.reload(using: services)
        #expect(session.subscriptions.first?.revision == 2)
        #expect(session.editingSubscription?.revision == 1)
        await #expect(throws: SubscriptionStore.StoreError.revisionConflict) {
            try await store.update(input, expectedRevision: 1, historyPolicy: .currentOnly)
        }
    }

    @Test func invalidRecordsRemainStoredAndProduceAVisibleWarning() async throws {
        let services = AppServices(inMemory: true)
        let container = try #require(services.modelContainer)
        container.mainContext.insert(SubscriptionRecord(input: makeInput(
            name: "Valid", state: .active, expiry: nil
        )))
        let invalid = SubscriptionRecord(input: makeInput(
            name: "Invalid", state: .active, expiry: nil
        ))
        invalid.categoryRaw = "unknown-category"
        container.mainContext.insert(invalid)
        try container.mainContext.save()
        let session = WindowSession()
        await session.reload(using: services)
        #expect(session.subscriptions.map(\.name) == ["Valid"])
        #expect(session.loadError == nil)
        #expect(session.invalidSubscriptionCount == 1)
        #expect(session.partialLoadWarning != nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SubscriptionRecord>()) == 2)
        let store = try #require(services.subscriptionStore)
        await #expect(throws: SubscriptionLoadError.self) { try await store.fetchAll() }
    }

    @Test func simultaneousReloadsShareTheSameLoad() async {
        let services = AppServices(inMemory: true)
        let session = WindowSession()
        async let first: Void = session.reload(using: services)
        async let second: Void = session.reload(using: services)
        _ = await (first, second)
        #expect(session.exchangeRateRefreshRevision == 1)
        #expect(!session.isLoading)
        #expect(session.hasLoadedSubscriptions)
    }

    @Test func dateContextReloadBypassesDataVersionCoalescing() async {
        let services = AppServices(inMemory: true)
        let session = WindowSession()
        async let first: Void = session.reload(using: services)
        async let second: Void = session.reload(using: services)
        _ = await (first, second)
        let coalescedRevision = session.exchangeRateRefreshRevision

        await session.reload(using: services, reason: .dateContextChange)

        #expect(coalescedRevision == 1)
        #expect(session.exchangeRateRefreshRevision == coalescedRevision + 1)
    }

    @Test func dismissedInvalidRecordWarningDoesNotReappearOnReload() async throws {
        let services = AppServices(inMemory: true)
        let container = try #require(services.modelContainer)
        let valid = SubscriptionRecord(input: makeInput(name: "Valid", state: .active, expiry: nil))
        let invalid = SubscriptionRecord(input: makeInput(name: "Invalid", state: .active, expiry: nil))
        invalid.categoryRaw = "unknown-category"
        container.mainContext.insert(valid)
        container.mainContext.insert(invalid)
        try container.mainContext.save()
        let session = WindowSession()
        await session.reload(using: services)
        session.loadError = nil

        services.notifySubscriptionDataChanged()
        await session.reload(using: services)
        #expect(session.loadError == nil)
        await session.reload(using: services)
        #expect(session.loadError == nil)
        #expect(session.invalidSubscriptionCount == 1)
        #expect(session.partialLoadWarning != nil)
        #expect(session.subscriptions.map(\.name) == ["Valid"])
        let store = try #require(services.subscriptionStore)
        let preview = try await store.previewDeletion([
            SubscriptionMutationTarget(id: invalid.id, expectedRevision: 1)
        ])
        _ = try await store.delete(preview)
        await session.reload(using: services)
        #expect(session.invalidSubscriptionCount == 0)
        #expect(session.partialLoadWarning == nil)
    }

    @Test func whollyInvalidSubscriptionsKeepANonmodalWarningAndStrictReadsFail() async throws {
        let services = AppServices(inMemory: true)
        let container = try #require(services.modelContainer)
        let invalid = SubscriptionRecord(input: makeInput(name: "Invalid", state: .active, expiry: nil))
        invalid.categoryRaw = "unknown-category"
        container.mainContext.insert(invalid)
        try container.mainContext.save()
        let session = WindowSession()
        await session.reload(using: services)
        #expect(session.subscriptions.isEmpty)
        #expect(session.invalidSubscriptionCount == 1)
        #expect(session.partialLoadWarning != nil)
        #expect(session.loadError == nil)
        await session.reload(using: services)
        #expect(session.loadError == nil)
        #expect(session.invalidSubscriptionCount == 1)
        let store = try #require(services.subscriptionStore)
        await #expect(throws: SubscriptionLoadError.self) { try await store.fetchAll() }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SubscriptionRecord>()) == 1)
    }

    @Test func expiryFiltersRemainIndependentOfManagementState() async throws {
        let services = AppServices(inMemory: true)
        let store = try #require(services.subscriptionStore)
        let today = LocalDate.today
        let yesterday = try #require(today.addingDays(-1))
        var inputs: [SubscriptionCreateInput] = []
        for state in ManagementState.allCases {
            inputs.append(makeInput(name: "Expired", state: state, expiry: yesterday))
            inputs.append(makeInput(name: "Effective", state: state, expiry: today))
            inputs.append(makeInput(name: "Unknown", state: state, expiry: nil))
            inputs.append(makeInput(name: "Lifetime", state: state, billingKind: .lifetime, expiry: nil))
        }
        try await store.create(inputs)
        let session = WindowSession()
        await session.reload(using: services)

        for state in ManagementState.allCases {
            session.overviewManagementState = state
            for (filter, expectedName) in [
                (OverviewExpiryFilter.expired, "Expired"),
                (.effective, "Effective"),
                (.unknownDate, "Unknown"),
                (.lifetime, "Lifetime"),
            ] {
                session.overviewExpiryFilter = filter
                #expect(session.filteredItems.map(\.name) == [expectedName])
                #expect(session.filteredItems.allSatisfy { $0.managementState == state })
            }
        }
        session.clearOverviewFilters()
        #expect(session.filteredItems.count == inputs.count)
    }

    private func makeInput(
        name: String,
        state: ManagementState,
        billingKind: BillingKind = .recurring,
        expiry: LocalDate?
    ) -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: UUID(),
            name: name,
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: state,
            billingKind: billingKind,
            periodStart: nil,
            expiry: expiry,
            cycleMonths: billingKind == .recurring ? 1 : nil,
            money: Money(minorUnits: 1_999, currency: .usd),
            note: "",
            reminderEnabled: false
        )
    }
}
