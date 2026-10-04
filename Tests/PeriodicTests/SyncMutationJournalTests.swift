import Foundation
import SwiftData
import Testing
@testable import Periodic

struct SyncMutationJournalTests {
    @MainActor
    @Test func recordsCreateUpdateAndDeleteAsOneRevisionChain() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let deviceID = UUID()
        let recordID = UUID().uuidString

        try SyncMutationJournal.recordCreate(
            in: context,
            deviceID: deviceID,
            recordType: .subscription,
            recordID: recordID,
            fieldValues: [
                "name": .string("Periodic"),
                "note": .string(""),
            ]
        )
        try SyncMutationJournal.recordUpdate(
            in: context,
            deviceID: deviceID,
            recordType: .subscription,
            recordID: recordID,
            previous: [
                "name": .string("Periodic"),
                "note": .string(""),
            ],
            current: [
                "name": .string("Periodic"),
                "note": .string("Edited"),
            ]
        )
        try SyncMutationJournal.recordDelete(
            in: context,
            deviceID: deviceID,
            recordType: .subscription,
            recordID: recordID
        )
        try context.save()

        let mutations = try context.fetch(
            FetchDescriptor<SyncMutationRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
        )
        #expect(mutations.map(\.baseRevision) == [0, 1, 2])
        #expect(mutations.map(\.targetRevision) == [1, 2, 3])
        #expect(
            try SyncMutationJournal.changedFields(from: mutations[1])
                == ["note"]
        )
        #expect(
            try SyncMutationJournal.fieldValues(from: mutations[1])
                == ["note": .string("Edited")]
        )

        let state = try #require(
            context.fetch(FetchDescriptor<SyncRecordStateRecord>()).first
        )
        #expect(state.revision == 3)
        #expect(state.isDeleted)
        #expect(state.deletedAt != nil)
        #expect(state.modifiedByDeviceID == deviceID)
    }

    @MainActor
    @Test func doesNotCreateAMutationForAnUnchangedSnapshot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let values = ["name": SyncValue.string("Periodic")]

        try SyncMutationJournal.recordCreate(
            in: context,
            deviceID: UUID(),
            recordType: .subscription,
            recordID: UUID().uuidString,
            fieldValues: values
        )
        let update = try SyncMutationJournal.recordUpdate(
            in: context,
            deviceID: UUID(),
            recordType: .subscription,
            recordID: UUID().uuidString,
            previous: values,
            current: values
        )

        #expect(update == nil)
        #expect(
            try context.fetch(FetchDescriptor<SyncMutationRecord>()).count == 1
        )
    }

    @MainActor
    @Test func blocksAnUpdateAfterATombstone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recordID = UUID().uuidString
        let deviceID = UUID()
        let values = ["name": SyncValue.string("Periodic")]

        try SyncMutationJournal.recordCreate(
            in: context,
            deviceID: deviceID,
            recordType: .subscription,
            recordID: recordID,
            fieldValues: values
        )
        try SyncMutationJournal.recordDelete(
            in: context,
            deviceID: deviceID,
            recordType: .subscription,
            recordID: recordID
        )

        #expect(throws: SyncMutationJournalError.cannotModifyDeletedRecord) {
            try SyncMutationJournal.recordUpdate(
                in: context,
                deviceID: deviceID,
                recordType: .subscription,
                recordID: recordID,
                previous: values,
                current: ["name": .string("Restored")]
            )
        }
    }

    @MainActor
    @Test func subscriptionStorePersistsFieldChangesAndDeletionTombstone() async throws {
        let container = try makeContainer()
        let deviceID = UUID()
        let access = DatasetAccessCoordinator(
            descriptor: .local(datasetID: UUID()),
            deviceID: deviceID
        )
        let store = SubscriptionStore(
            modelContainer: container,
            datasetAccess: access
        )
        let subscriptionID = UUID()
        let original = SubscriptionCreateInput(
            id: subscriptionID,
            name: "Sync Test",
            symbolName: "arrow.triangle.2.circlepath",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: LocalDate(dayNumber: 20_000),
            expiry: LocalDate(dayNumber: 20_030),
            cycleMonths: 1,
            money: Money(minorUnits: 1_200, currency: .cny),
            note: "",
            reminderEnabled: false
        )
        _ = try await store.create(
            original,
            historyPolicy: .skipInitialPeriod
        )
        let created = try #require(try await store.fetchAll().first)
        let updated = SubscriptionCreateInput(
            id: subscriptionID,
            name: original.name,
            symbolName: original.symbolName,
            iconResourceName: original.iconResourceName,
            iconURLString: original.iconURLString,
            category: original.category,
            managementState: original.managementState,
            billingKind: original.billingKind,
            periodStart: original.periodStart,
            expiry: original.expiry,
            cycleMonths: original.cycleMonths,
            money: original.money,
            note: "Changed",
            reminderEnabled: original.reminderEnabled
        )
        try await store.update(
            updated,
            expectedRevision: created.revision,
            historyPolicy: .currentOnly
        )
        let current = try #require(try await store.fetchAll().first)
        let preview = try await store.previewDeletion([
            SubscriptionMutationTarget(
                id: subscriptionID,
                expectedRevision: current.revision
            ),
        ])
        _ = try await store.delete(preview)

        let context = ModelContext(container)
        let recordID = subscriptionID.uuidString
        let mutations = try context.fetch(
            FetchDescriptor<SyncMutationRecord>(
                predicate: #Predicate {
                    $0.recordID == recordID
                },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
        )
        #expect(
            mutations.compactMap {
                SyncMutationOperation(rawValue: $0.operationRaw)
            }
                == [.create, .update, .delete]
        )
        #expect(
            try SyncMutationJournal.changedFields(from: mutations[1])
                == ["note"]
        )
        #expect(mutations.allSatisfy { $0.deviceID == deviceID })

        let stateKey = SyncRecordStateRecord.key(
            recordType: .subscription,
            recordID: recordID
        )
        let state = try #require(
            context.fetch(
                FetchDescriptor<SyncRecordStateRecord>(
                    predicate: #Predicate { $0.recordKey == stateKey }
                )
            ).first
        )
        #expect(state.isDeleted)
        #expect(state.revision == 3)
    }

    @MainActor
    @Test func mutationStoreUsesExplicitRetryAndAcknowledgementTransitions() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mutation = try SyncMutationJournal.recordCreate(
            in: context,
            deviceID: UUID(),
            recordType: .subscription,
            recordID: UUID().uuidString,
            fieldValues: ["name": .string("Periodic")]
        )
        try context.save()
        let store = SyncMutationStore(modelContainer: container)

        let pending = try await store.fetchPending()
        #expect(pending.map(\.mutationID) == [mutation.mutationID])
        try await store.markUploading([mutation.mutationID])
        #expect(try await store.fetchPending().isEmpty)

        try await store.markPending([mutation.mutationID])
        #expect(try await store.fetchPending().count == 1)
        try await store.markUploading([mutation.mutationID])
        try await store.markAcknowledged([mutation.mutationID])
        #expect(try await store.removeAcknowledged() == 1)
        #expect(
            try ModelContext(container)
                .fetch(FetchDescriptor<SyncMutationRecord>()).isEmpty
        )
    }

    @MainActor
    @Test func uploadAcknowledgementAtomicallyStoresSystemFieldsAndRemovesMutations() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recordID = UUID().uuidString
        let mutation = try SyncMutationJournal.recordCreate(
            in: context,
            deviceID: UUID(),
            recordType: .subscription,
            recordID: recordID,
            fieldValues: ["name": .string("Periodic")]
        )
        try context.save()
        let systemFields = Data([1, 2, 3])

        try await SyncMutationStore(
            modelContainer: container
        ).acknowledgeUpload(
            mutationIDs: [mutation.mutationID],
            recordType: .subscription,
            recordID: recordID,
            serverRecordData: systemFields
        )

        let verification = ModelContext(container)
        #expect(
            try verification.fetch(FetchDescriptor<SyncMutationRecord>())
                .isEmpty
        )
        #expect(
            try verification.fetch(FetchDescriptor<SyncRecordStateRecord>())
                .first?
                .serverRecordData == systemFields
        )
    }

    @MainActor
    @Test func bootstrapQueuesLegacyRecordsExactlyOnce() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let subscriptionID = UUID()
        let input = SubscriptionCreateInput(
            id: subscriptionID,
            name: "Legacy",
            symbolName: "clock",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: LocalDate(dayNumber: 20_000),
            expiry: LocalDate(dayNumber: 20_030),
            cycleMonths: 1,
            money: Money(minorUnits: 990, currency: .cny),
            note: "",
            reminderEnabled: false
        )
        context.insert(SubscriptionRecord(input: input))
        context.insert(
            SubscriptionPeriodRecord(
                input: SubscriptionPeriodCreateInput(
                    id: UUID(),
                    subscriptionID: subscriptionID,
                    billingKind: .recurring,
                    cycleMonths: 1,
                    start: try #require(input.periodStart),
                    end: input.expiry,
                    money: input.money
                )
            )
        )
        try context.save()
        let access = DatasetAccessCoordinator(
            descriptor: .local(datasetID: UUID()),
            deviceID: UUID()
        )
        let bootstrap = SyncBootstrapStore(
            modelContainer: container,
            datasetAccess: access
        )

        #expect(
            try await bootstrap.bootstrapExistingRecords()
                .createdMutationCount == 2
        )
        #expect(
            try await bootstrap.bootstrapExistingRecords()
                .createdMutationCount == 0
        )
        #expect(
            try ModelContext(container)
                .fetch(FetchDescriptor<SyncMutationRecord>()).count == 2
        )
    }

    @MainActor
    @Test func recordsAssetDeletionBeforeManagedFileCleanup() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let access = DatasetAccessCoordinator(
            descriptor: .local(datasetID: UUID()),
            deviceID: UUID()
        )
        let reference = AppleIconCache.localReferencePrefix
            + String(repeating: "a", count: 64)
        try SyncMutationJournal.recordCreate(
            in: context,
            deviceID: access.deviceID,
            recordType: .iconAsset,
            recordID: reference,
            fieldValues: SyncRecordPayload.iconAsset(
                reference: reference,
                metadata: CloudAssetMetadata(
                    contentHash: String(repeating: "a", count: 64),
                    format: .png,
                    byteCount: 64
                )
            )
        )
        try context.save()
        let bootstrap = SyncBootstrapStore(
            modelContainer: container,
            datasetAccess: access
        )

        let receipt = try await bootstrap.recordAssetDeletions(
            references: [reference]
        )

        #expect(receipt.createdMutationCount == 1)
        let verification = ModelContext(container)
        let mutations = try verification.fetch(
            FetchDescriptor<SyncMutationRecord>(
                sortBy: [SortDescriptor(\.targetRevision)]
            )
        )
        #expect(
            mutations.compactMap {
                SyncMutationOperation(rawValue: $0.operationRaw)
            } == [.create, .delete]
        )
        let state = try #require(
            verification.fetch(
                FetchDescriptor<SyncRecordStateRecord>()
            ).first
        )
        #expect(state.isDeleted)
        #expect(state.revision == 2)
        #expect(
            try await bootstrap.recordAssetDeletions(
                references: [reference]
            ).createdMutationCount == 0
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController().makeContainer(
            schema: Schema(versionedSchema: AppSchemaV9.self),
            inMemory: true
        )
    }
}
