import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Periodic

struct SyncRemoteChangeApplierTests {
    @MainActor
    @Test func twoLocalStoresConvergeDifferentOfflineFields() async throws {
        let firstContainer = try makeContainer()
        let secondContainer = try makeContainer()
        let firstAccess = datasetAccess()
        let secondAccess = datasetAccess()
        let subscriptionID = UUID()
        let original = subscriptionInput(
            id: subscriptionID,
            name: "Original"
        )
        let firstStore = SubscriptionStore(
            modelContainer: firstContainer,
            datasetAccess: firstAccess
        )
        _ = try await firstStore.create(
            original,
            historyPolicy: .skipInitialPeriod
        )

        let initialChange = try await uploadChange(
            sourceChangeID: "initial-upload",
            container: firstContainer,
            access: firstAccess,
            acknowledgesMutations: true
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: secondContainer,
            datasetAccess: secondAccess
        ).enqueue([initialChange])
        _ = try await SyncRemoteChangeApplier(
            modelContainer: secondContainer,
            datasetAccess: secondAccess
        ).applyPending()

        let secondStore = SubscriptionStore(
            modelContainer: secondContainer,
            datasetAccess: secondAccess
        )
        let firstBaseline = try #require(
            try await firstStore.fetchAll().first
        )
        let secondBaseline = try #require(
            try await secondStore.fetchAll().first
        )
        try await firstStore.update(
            subscriptionInput(
                id: subscriptionID,
                name: "Changed on A"
            ),
            expectedRevision: firstBaseline.revision,
            historyPolicy: .currentOnly
        )
        try await secondStore.update(
            subscriptionInput(
                id: subscriptionID,
                name: "Original",
                note: "Changed on B"
            ),
            expectedRevision: secondBaseline.revision,
            historyPolicy: .currentOnly
        )

        let updateFromFirst = try await uploadChange(
            sourceChangeID: "device-a-update",
            container: firstContainer,
            access: firstAccess
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: secondContainer,
            datasetAccess: secondAccess
        ).enqueue([updateFromFirst])
        let report = try await SyncRemoteChangeApplier(
            modelContainer: secondContainer,
            datasetAccess: secondAccess
        ).applyPending()
        let converged = try #require(
            try await secondStore.fetchAll().first
        )

        #expect(report.appliedCount == 1)
        #expect(converged.name == "Changed on A")
        #expect(converged.note == "Changed on B")
        let pending = try await SyncMutationStore(
            modelContainer: secondContainer,
            datasetAccess: secondAccess
        ).fetchPending()
        #expect(pending.count == 1)
        #expect(pending.first?.baseRevision == 2)
        #expect(pending.first?.targetRevision == 3)
        #expect(pending.first?.fieldValues == ["note": .string("Changed on B")])
    }

    @MainActor
    @Test func durableInboxReplaysAfterStoreReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let storeURL = directory.appending(path: "Periodic.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let datasetID = UUID()
        let deviceID = UUID()
        let input = subscriptionInput(name: "Remote")
        let change = try subscriptionChange(
            sourceChangeID: "subscription-create",
            input: input,
            revision: 1,
            baseRevision: 0,
            changedFields: Set(subscriptionFields(input).keys)
        )

        do {
            let container = try makeContainer(storeURL: storeURL)
            let access = datasetAccess(
                datasetID: datasetID,
                deviceID: deviceID
            )
            let inbox = SyncRemoteInboxStore(
                modelContainer: container,
                datasetAccess: access
            )
            #expect(try await inbox.enqueue([change]) == 1)
            #expect(try await inbox.enqueue([change]) == 0)
        }

        let reopened = try makeContainer(storeURL: storeURL)
        let access = datasetAccess(
            datasetID: datasetID,
            deviceID: deviceID
        )
        let report = try await SyncRemoteChangeApplier(
            modelContainer: reopened,
            datasetAccess: access
        ).applyPending()

        #expect(report.appliedCount == 1)
        #expect(report.failedCount == 0)
        #expect(
            try await SubscriptionStore(
                modelContainer: reopened,
                datasetAccess: access
            ).fetchAll().map(\.name) == ["Remote"]
        )
        let context = ModelContext(reopened)
        #expect(
            try context.fetch(FetchDescriptor<SyncRemoteChangeRecord>())
                .first?
                .stateRaw == SyncRemoteChangeState.applied.rawValue
        )
    }

    @MainActor
    @Test func appliesParentBeforePeriodRegardlessOfArrivalOrder() async throws {
        let container = try makeContainer()
        let access = datasetAccess()
        let input = subscriptionInput(name: "Parent")
        let periodID = UUID()
        let period = SubscriptionPeriodCreateInput(
            id: periodID,
            subscriptionID: input.id,
            billingKind: .recurring,
            cycleMonths: 1,
            start: try #require(input.periodStart),
            end: input.expiry,
            money: input.money,
            source: .manual
        )
        let periodChange = try self.periodChange(
            sourceChangeID: "period-first",
            input: period,
            revision: 1,
            baseRevision: 0,
            receivedAt: Date(timeIntervalSince1970: 1)
        )
        let subscriptionChange = try subscriptionChange(
            sourceChangeID: "subscription-second",
            input: input,
            revision: 1,
            baseRevision: 0,
            changedFields: Set(subscriptionFields(input).keys),
            receivedAt: Date(timeIntervalSince1970: 2)
        )
        let inbox = SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        )
        _ = try await inbox.enqueue([periodChange, subscriptionChange])

        let report = try await SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access
        ).applyPending()
        let detail = try await SubscriptionStore(
            modelContainer: container,
            datasetAccess: access
        ).fetchDetail(for: input.id)

        #expect(report.appliedCount == 2)
        #expect(report.deferredCount == 0)
        #expect(detail.periods.map(\.id) == [periodID])
        #expect(detail.subscription.revision == 2)
    }

    @MainActor
    @Test func automaticallyMergesDifferentFieldsAndRebasesPendingMutation() async throws {
        let container = try makeContainer()
        let access = datasetAccess()
        let original = subscriptionInput(name: "Original", note: "")
        try await applyBaseline(
            original,
            container: container,
            access: access
        )

        let subscriptionStore = SubscriptionStore(
            modelContainer: container,
            datasetAccess: access
        )
        let baseline = try #require(try await subscriptionStore.fetchAll().first)
        let local = subscriptionInput(
            id: original.id,
            name: "Original",
            note: "Local note"
        )
        try await subscriptionStore.update(
            local,
            expectedRevision: baseline.revision,
            historyPolicy: .currentOnly
        )

        let remote = subscriptionInput(
            id: original.id,
            name: "Remote name",
            note: ""
        )
        let remoteChange = try subscriptionChange(
            sourceChangeID: "remote-name",
            input: remote,
            revision: 2,
            baseRevision: 1,
            changedFields: ["name"]
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        ).enqueue([remoteChange])
        let report = try await SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access
        ).applyPending()
        let merged = try #require(
            try await subscriptionStore.fetchAll().first
        )

        #expect(report.appliedCount == 1)
        #expect(report.conflictCount == 0)
        #expect(merged.name == "Remote name")
        #expect(merged.note == "Local note")

        let context = ModelContext(container)
        let mutations = try context.fetch(
            FetchDescriptor<SyncMutationRecord>()
        )
        #expect(mutations.count == 1)
        #expect(mutations.first?.baseRevision == 2)
        #expect(mutations.first?.targetRevision == 3)
        #expect(
            try mutations.first.map(SyncMutationJournal.changedFields)
                == ["note"]
        )
        let state = try #require(
            context.fetch(FetchDescriptor<SyncRecordStateRecord>()).first
        )
        #expect(state.revision == 3)
        #expect(state.modifiedByDeviceID == access.deviceID)
    }

    @MainActor
    @Test func persistsSameFieldConflictWithoutOverwritingLocalValue() async throws {
        let container = try makeContainer()
        let access = datasetAccess()
        let original = subscriptionInput(name: "Original")
        try await applyBaseline(
            original,
            container: container,
            access: access
        )

        let subscriptionStore = SubscriptionStore(
            modelContainer: container,
            datasetAccess: access
        )
        let baseline = try #require(try await subscriptionStore.fetchAll().first)
        try await subscriptionStore.update(
            subscriptionInput(id: original.id, name: "Local"),
            expectedRevision: baseline.revision,
            historyPolicy: .currentOnly
        )
        let remoteChange = try subscriptionChange(
            sourceChangeID: "same-field-conflict",
            input: subscriptionInput(id: original.id, name: "Remote"),
            revision: 2,
            baseRevision: 1,
            changedFields: ["name"]
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        ).enqueue([remoteChange])
        let report = try await SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access
        ).applyPending()

        #expect(report.conflictCount == 1)
        #expect(
            try await subscriptionStore.fetchAll().first?.name == "Local"
        )
        let context = ModelContext(container)
        let conflict = try #require(
            context.fetch(FetchDescriptor<SyncConflictRecord>()).first
        )
        let payload = try JSONDecoder().decode(
            SyncConflictPayload.self,
            from: conflict.payloadData
        )
        #expect(payload.reasons.contains(.fields(["name"])))
        #expect(
            try context.fetch(FetchDescriptor<SyncMutationRecord>())
                .allSatisfy {
                    $0.stateRaw == SyncMutationState.conflicted.rawValue
                }
        )
        #expect(
            try context.fetch(FetchDescriptor<SyncRemoteChangeRecord>())
                .last?
                .stateRaw == SyncRemoteChangeState.conflicted.rawValue
        )
    }

    @MainActor
    @Test func resolvesSameFieldConflictKeepingLocalValue() async throws {
        let container = try makeContainer()
        let access = datasetAccess()
        let original = subscriptionInput(name: "Original")
        try await applyBaseline(
            original,
            container: container,
            access: access
        )
        let store = SubscriptionStore(
            modelContainer: container,
            datasetAccess: access
        )
        let baseline = try #require(try await store.fetchAll().first)
        try await store.update(
            subscriptionInput(id: original.id, name: "Local"),
            expectedRevision: baseline.revision,
            historyPolicy: .currentOnly
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        ).enqueue([
            try subscriptionChange(
                sourceChangeID: "resolve-local",
                input: subscriptionInput(
                    id: original.id,
                    name: "Remote"
                ),
                revision: 2,
                baseRevision: 1,
                changedFields: ["name"]
            ),
        ])
        let applier = SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access
        )
        #expect(try await applier.applyPending().conflictCount == 1)
        let conflictID = try #require(
            ModelContext(container)
                .fetch(FetchDescriptor<SyncConflictRecord>())
                .first?
                .conflictID
        )

        try await applier.resolveConflict(
            conflictID,
            resolution: .keepLocal
        )

        #expect(try await store.fetchAll().first?.name == "Local")
        let context = ModelContext(container)
        let mutation = try #require(
            context.fetch(FetchDescriptor<SyncMutationRecord>()).first
        )
        #expect(mutation.baseRevision == 2)
        #expect(mutation.targetRevision == 3)
        #expect(mutation.stateRaw == SyncMutationState.pending.rawValue)
        #expect(
            try context.fetch(FetchDescriptor<SyncConflictRecord>())
                .first?
                .stateRaw == SyncConflictState.resolved.rawValue
        )
        #expect(
            try context.fetch(FetchDescriptor<SyncRemoteChangeRecord>())
                .first?
                .stateRaw == SyncRemoteChangeState.applied.rawValue
        )
    }

    @MainActor
    @Test func resolvesSameFieldConflictUsingRemoteValue() async throws {
        let container = try makeContainer()
        let access = datasetAccess()
        let original = subscriptionInput(name: "Original")
        try await applyBaseline(
            original,
            container: container,
            access: access
        )
        let store = SubscriptionStore(
            modelContainer: container,
            datasetAccess: access
        )
        let baseline = try #require(try await store.fetchAll().first)
        try await store.update(
            subscriptionInput(id: original.id, name: "Local"),
            expectedRevision: baseline.revision,
            historyPolicy: .currentOnly
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        ).enqueue([
            try subscriptionChange(
                sourceChangeID: "resolve-remote",
                input: subscriptionInput(
                    id: original.id,
                    name: "Remote"
                ),
                revision: 2,
                baseRevision: 1,
                changedFields: ["name"]
            ),
        ])
        let applier = SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access
        )
        #expect(try await applier.applyPending().conflictCount == 1)
        let conflictID = try #require(
            ModelContext(container)
                .fetch(FetchDescriptor<SyncConflictRecord>())
                .first?
                .conflictID
        )

        try await applier.resolveConflict(
            conflictID,
            resolution: .useRemote
        )

        #expect(try await store.fetchAll().first?.name == "Remote")
        let context = ModelContext(container)
        #expect(
            try context.fetch(FetchDescriptor<SyncMutationRecord>()).isEmpty
        )
        #expect(
            try context.fetch(FetchDescriptor<SyncConflictRecord>())
                .first?
                .stateRaw == SyncConflictState.resolved.rawValue
        )
        #expect(
            try context.fetch(FetchDescriptor<SyncRemoteChangeRecord>())
                .first?
                .stateRaw == SyncRemoteChangeState.applied.rawValue
        )
    }

    @MainActor
    @Test func persistsDeleteVersusOfflineModificationConflict() async throws {
        let container = try makeContainer()
        let access = datasetAccess()
        let original = subscriptionInput(name: "Keep Local")
        try await applyBaseline(
            original,
            container: container,
            access: access
        )
        let store = SubscriptionStore(
            modelContainer: container,
            datasetAccess: access
        )
        let baseline = try #require(try await store.fetchAll().first)
        try await store.update(
            subscriptionInput(
                id: original.id,
                name: original.name,
                note: "Offline edit"
            ),
            expectedRevision: baseline.revision,
            historyPolicy: .currentOnly
        )
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let deletion = try remoteChange(
            sourceChangeID: "remote-delete",
            envelope: CloudRecordEnvelope(
                recordType: .subscription,
                recordID: original.id.uuidString,
                revision: 2,
                modifiedAt: deletedAt,
                modifiedByDeviceID: UUID(),
                isDeleted: true,
                deletedAt: deletedAt,
                fieldValues: [:],
                baseRevision: 1,
                changedFields: [],
                relationshipChanges: []
            ),
            receivedAt: deletedAt
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        ).enqueue([deletion])
        let report = try await SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access
        ).applyPending()

        #expect(report.conflictCount == 1)
        #expect(try await store.fetchAll().first?.note == "Offline edit")
        let payload = try JSONDecoder().decode(
            SyncConflictPayload.self,
            from: try #require(
                ModelContext(container)
                    .fetch(FetchDescriptor<SyncConflictRecord>())
                    .first
            ).payloadData
        )
        #expect(payload.reasons.contains(.deletionVersusModification))
    }

    @MainActor
    @Test func doesNotOverwriteAnUntrackedLegacyRecord() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let local = subscriptionInput(name: "Local legacy")
        context.insert(SubscriptionRecord(input: local))
        try context.save()
        let access = datasetAccess()
        let remote = subscriptionInput(
            id: local.id,
            name: "Remote replacement"
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        ).enqueue([
            try subscriptionChange(
                sourceChangeID: "legacy-overwrite",
                input: remote,
                revision: 1,
                baseRevision: 0,
                changedFields: Set(subscriptionFields(remote).keys)
            ),
        ])
        let report = try await SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access
        ).applyPending()

        #expect(report.failedCount == 1)
        #expect(
            try await SubscriptionStore(
                modelContainer: container,
                datasetAccess: access
            ).fetchAll().first?.name == "Local legacy"
        )
        #expect(
            try ModelContext(container)
                .fetch(FetchDescriptor<SyncRemoteChangeRecord>())
                .first?
                .failureCode == "invalidLocalState"
        )
    }

    @MainActor
    @Test func defersPeriodUntilItsParentArrives() async throws {
        let container = try makeContainer()
        let access = datasetAccess()
        let input = subscriptionInput(name: "Later Parent")
        let period = SubscriptionPeriodCreateInput(
            id: UUID(),
            subscriptionID: input.id,
            billingKind: .recurring,
            cycleMonths: 1,
            start: try #require(input.periodStart),
            end: input.expiry,
            money: input.money,
            source: .manual
        )
        let inbox = SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        )
        _ = try await inbox.enqueue([
            try periodChange(
                sourceChangeID: "orphan-period",
                input: period,
                revision: 1,
                baseRevision: 0
            ),
        ])
        let applier = SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access
        )

        let deferred = try await applier.applyPending()
        #expect(deferred.deferredCount == 1)
        #expect(deferred.failedCount == 0)

        _ = try await inbox.enqueue([
            try subscriptionChange(
                sourceChangeID: "late-parent",
                input: input,
                revision: 1,
                baseRevision: 0,
                changedFields: Set(subscriptionFields(input).keys)
            ),
        ])
        let retried = try await applier.applyPending()

        #expect(retried.appliedCount == 2)
        #expect(
            try await SubscriptionStore(
                modelContainer: container,
                datasetAccess: access
            ).fetchPeriods(for: input.id).map(\.id) == [period.id]
        )
    }

    @MainActor
    @Test func appliesPaymentTemplateCategoryAndBuiltinAssignment() async throws {
        let firstContainer = try makeContainer()
        let secondContainer = try makeContainer()
        let firstAccess = datasetAccess()
        let secondAccess = datasetAccess()
        let subscription = subscriptionInput(name: "Synced Service")
        let firstSubscriptionStore = SubscriptionStore(
            modelContainer: firstContainer,
            datasetAccess: firstAccess
        )
        _ = try await firstSubscriptionStore.create(
            subscription,
            historyPolicy: .skipInitialPeriod
        )
        let categoryID = UUID()
        try await TemplateCategoryStore(
            modelContainer: firstContainer,
            datasetAccess: firstAccess
        ).save(
            TemplateCategoryInput(
                id: categoryID,
                expectedRevision: nil,
                name: "Cloud Category"
            )
        )
        let templateID = UUID()
        try await TemplateStore(
            modelContainer: firstContainer,
            datasetAccess: firstAccess
        ).save(
            ServiceTemplateInput(
                id: templateID,
                expectedRevision: nil,
                name: "Cloud Template",
                aliases: ["Remote"],
                category: .other,
                customCategoryID: categoryID,
                symbolName: "cloud",
                iconResourceName: nil,
                iconURLString: nil,
                suggestedBillingKind: .recurring,
                suggestedCycleMonths: 1,
                suggestedMoney: Money(minorUnits: 600, currency: .cny),
                currency: .cny
            )
        )
        try await BuiltinTemplateCategoryStore(
            modelContainer: firstContainer,
            datasetAccess: firstAccess
        ).assign(
            .custom(categoryID),
            toBuiltinTemplate: "builtin.cloud"
        )
        let createdSubscription = try #require(
            try await firstSubscriptionStore.fetchAll().first
        )
        let paymentID = UUID()
        try await firstSubscriptionStore.addPayment(
            SubscriptionPaymentAddInput(
                payment: SubscriptionPaymentCreateInput(
                    id: paymentID,
                    subscriptionID: subscription.id,
                    periodRecordID: nil,
                    kind: .manual,
                    paymentDate: LocalDate(dayNumber: 20_000),
                    money: Money(minorUnits: 1_200, currency: .cny),
                    periodStart: nil,
                    periodEnd: nil,
                    note: "Cloud payment",
                    attachmentReferences: []
                ),
                expectedSubscriptionRevision: createdSubscription.revision
            )
        )

        let changes = try await uploadChanges(
            container: firstContainer,
            access: firstAccess
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: secondContainer,
            datasetAccess: secondAccess
        ).enqueue(changes)
        let report = try await SyncRemoteChangeApplier(
            modelContainer: secondContainer,
            datasetAccess: secondAccess
        ).applyPending(limit: 100)

        #expect(report.failedCount == 0)
        #expect(report.deferredCount == 0)
        #expect(report.appliedCount == changes.count)
        #expect(
            try await SubscriptionStore(
                modelContainer: secondContainer,
                datasetAccess: secondAccess
            ).fetchPayments(for: subscription.id).map(\.id) == [paymentID]
        )
        #expect(
            try await TemplateCategoryStore(
                modelContainer: secondContainer,
                datasetAccess: secondAccess
            ).fetchAll().map(\.id) == [categoryID]
        )
        let templates = try await TemplateStore(
            modelContainer: secondContainer,
            datasetAccess: secondAccess
        ).fetchAll()
        #expect(templates.map(\.key) == [.user(templateID)])
        #expect(templates.first?.customCategoryID == categoryID)
        #expect(
            try await BuiltinTemplateCategoryStore(
                modelContainer: secondContainer,
                datasetAccess: secondAccess
            ).fetchAssignments()["builtin.cloud"] == .custom(categoryID)
        )
    }

    @MainActor
    @Test func waitsForSubscriptionIconBeforeApplyingReference() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try makeContainer()
        let access = datasetAccess()
        let data = try cloudImageData()
        let metadata = assetMetadata(for: data)
        let reference = AppleIconCache.localReferencePrefix
            + metadata.contentHash
        let input = subscriptionInput(
            name: "Remote Icon",
            iconURLString: reference
        )
        let inbox = SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        )
        _ = try await inbox.enqueue([
            try subscriptionChange(
                sourceChangeID: "icon-subscription",
                input: input,
                revision: 1,
                baseRevision: 0,
                changedFields: Set(subscriptionFields(input).keys)
            ),
        ])
        let iconCache = AppleIconCache(storageRoot: root)
        let stagingRoot = root.appending(
            path: "CloudAssetStaging",
            directoryHint: .isDirectory
        )
        let repository = CloudAssetRepository(
            iconCache: iconCache,
            paymentAttachmentStore: PaymentAttachmentStore(
                storageRoot: root
            ),
            stager: CloudImageAssetStager(stagingRoot: stagingRoot)
        )
        let applier = SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access,
            assetRepository: repository
        )

        let deferred = try await applier.applyPending()

        #expect(deferred.deferredCount == 1)
        #expect(
            try await SubscriptionStore(
                modelContainer: container,
                datasetAccess: access
            ).fetchAll().isEmpty
        )

        let initialStager = CloudImageAssetStager(
            stagingRoot: stagingRoot
        )
        _ = try await initialStager.stage(
            data: data,
            expectedContentHash: metadata.contentHash
        )
        _ = try await inbox.enqueue([
            try assetChange(
                sourceChangeID: "subscription-icon-asset",
                reference: reference,
                data: data,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_200)
            ),
        ])

        let applied = try await applier.applyPending()
        let subscription = try #require(
            try await SubscriptionStore(
                modelContainer: container,
                datasetAccess: access
            ).fetchAll().first
        )

        #expect(applied.appliedCount == 2)
        #expect(applied.deferredCount == 0)
        #expect(subscription.iconURLString == reference)
        #expect(try await iconCache.data(for: reference) == data)
    }

    @MainActor
    @Test func waitsForPaymentAttachmentBeforeApplyingReference() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try makeContainer()
        let access = datasetAccess()
        let subscription = subscriptionInput(name: "Attachment Parent")
        try await applyBaseline(
            subscription,
            container: container,
            access: access
        )
        let data = try cloudImageData()
        let metadata = assetMetadata(for: data)
        let reference = PaymentAttachmentReference.make(
            contentHash: metadata.contentHash
        )
        let payment = SubscriptionPaymentCreateInput(
            id: UUID(),
            subscriptionID: subscription.id,
            periodRecordID: nil,
            kind: .manual,
            paymentDate: LocalDate(dayNumber: 20_000),
            money: Money(minorUnits: 1_200, currency: .cny),
            periodStart: nil,
            periodEnd: nil,
            note: "Cloud receipt",
            attachmentReferences: [reference]
        )
        let inbox = SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        )
        _ = try await inbox.enqueue([
            try paymentChange(
                sourceChangeID: "payment-before-asset",
                input: payment
            ),
        ])
        let attachmentStore = PaymentAttachmentStore(storageRoot: root)
        let stagingRoot = root.appending(
            path: "CloudAssetStaging",
            directoryHint: .isDirectory
        )
        let repository = CloudAssetRepository(
            iconCache: AppleIconCache(storageRoot: root),
            paymentAttachmentStore: attachmentStore,
            stager: CloudImageAssetStager(stagingRoot: stagingRoot)
        )
        let applier = SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access,
            assetRepository: repository
        )

        let deferred = try await applier.applyPending()

        #expect(deferred.deferredCount == 1)
        #expect(
            try await SubscriptionStore(
                modelContainer: container,
                datasetAccess: access
            ).fetchPayments(for: subscription.id).isEmpty
        )

        let initialStager = CloudImageAssetStager(
            stagingRoot: stagingRoot
        )
        _ = try await initialStager.stage(
            data: data,
            expectedContentHash: metadata.contentHash
        )
        _ = try await inbox.enqueue([
            try assetChange(
                sourceChangeID: "payment-attachment-asset",
                reference: reference,
                data: data,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_200)
            ),
        ])

        let applied = try await applier.applyPending()
        let storedPayment = try #require(
            try await SubscriptionStore(
                modelContainer: container,
                datasetAccess: access
            ).fetchPayments(for: subscription.id).first
        )

        #expect(applied.appliedCount == 2)
        #expect(applied.deferredCount == 0)
        #expect(storedPayment.attachmentReferences == [reference])
        #expect(try await attachmentStore.data(for: reference) == data)
    }

    @MainActor
    @Test func removesAssetAfterRemoteReferenceRemoval() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try makeContainer()
        let access = datasetAccess()
        let data = try cloudImageData()
        let metadata = assetMetadata(for: data)
        let reference = AppleIconCache.localReferencePrefix
            + metadata.contentHash
        let subscriptionID = UUID()
        let initialInput = subscriptionInput(
            id: subscriptionID,
            name: "Remote Icon",
            iconURLString: reference
        )
        let stagingRoot = root.appending(
            path: "CloudAssetStaging",
            directoryHint: .isDirectory
        )
        let initialStager = CloudImageAssetStager(
            stagingRoot: stagingRoot
        )
        _ = try await initialStager.stage(
            data: data,
            expectedContentHash: metadata.contentHash
        )
        let iconCache = AppleIconCache(storageRoot: root)
        let repository = CloudAssetRepository(
            iconCache: iconCache,
            paymentAttachmentStore: PaymentAttachmentStore(
                storageRoot: root
            ),
            stager: CloudImageAssetStager(stagingRoot: stagingRoot)
        )
        let inbox = SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        )
        _ = try await inbox.enqueue([
            try subscriptionChange(
                sourceChangeID: "asset-owner-create",
                input: initialInput,
                revision: 1,
                baseRevision: 0,
                changedFields: Set(
                    subscriptionFields(initialInput).keys
                )
            ),
            try assetChange(
                sourceChangeID: "owned-asset-create",
                reference: reference,
                data: data,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_200)
            ),
        ])
        let applier = SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access,
            assetRepository: repository
        )
        let created = try await applier.applyPending()
        #expect(created.appliedCount == 2)
        #expect(try await iconCache.data(for: reference) == data)

        let updatedInput = subscriptionInput(
            id: subscriptionID,
            name: "Remote Icon"
        )
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_400)
        _ = try await inbox.enqueue([
            try remoteChange(
                sourceChangeID: "owned-asset-delete",
                envelope: CloudRecordEnvelope(
                    recordType: .iconAsset,
                    recordID: reference,
                    revision: 2,
                    modifiedAt: deletedAt,
                    modifiedByDeviceID: UUID(),
                    isDeleted: true,
                    deletedAt: deletedAt,
                    fieldValues: [:],
                    baseRevision: 1,
                    changedFields: [],
                    relationshipChanges: []
                ),
                receivedAt: Date(timeIntervalSince1970: 1_700_000_300)
            ),
            try subscriptionChange(
                sourceChangeID: "asset-owner-update",
                input: updatedInput,
                revision: 2,
                baseRevision: 1,
                changedFields: ["iconURLString"],
                receivedAt: deletedAt
            ),
        ])

        let removed = try await applier.applyPending()
        let subscription = try #require(
            try await SubscriptionStore(
                modelContainer: container,
                datasetAccess: access
            ).fetchAll().first
        )

        #expect(removed.appliedCount == 2)
        #expect(removed.deferredCount == 0)
        #expect(subscription.iconURLString == nil)
        await #expect(throws: AppleIconCache.CacheError.storedImageMissing) {
            try await iconCache.data(for: reference)
        }
    }

    @MainActor
    private func applyBaseline(
        _ input: SubscriptionCreateInput,
        container: ModelContainer,
        access: DatasetAccessCoordinator
    ) async throws {
        let change = try subscriptionChange(
            sourceChangeID: "baseline-" + input.id.uuidString,
            input: input,
            revision: 1,
            baseRevision: 0,
            changedFields: Set(subscriptionFields(input).keys)
        )
        _ = try await SyncRemoteInboxStore(
            modelContainer: container,
            datasetAccess: access
        ).enqueue([change])
        let report = try await SyncRemoteChangeApplier(
            modelContainer: container,
            datasetAccess: access
        ).applyPending()
        #expect(report.appliedCount == 1)
    }

    @MainActor
    private func makeContainer(
        storeURL: URL? = nil
    ) throws -> ModelContainer {
        try PersistenceController(
            storeURL: storeURL ?? AppConfiguration.storeURL
        ).makeContainer(
            schema: Schema(versionedSchema: AppSchemaV9.self),
            migrationPlan: AppSchemaMigrationPlan.self,
            inMemory: storeURL == nil
        )
    }

    private func datasetAccess(
        datasetID: UUID = UUID(),
        deviceID: UUID = UUID()
    ) -> DatasetAccessCoordinator {
        DatasetAccessCoordinator(
            descriptor: .local(datasetID: datasetID),
            deviceID: deviceID
        )
    }

    private func subscriptionInput(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        iconURLString: String? = nil
    ) -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: id,
            name: name,
            symbolName: "cloud",
            iconResourceName: nil,
            iconURLString: iconURLString,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: LocalDate(dayNumber: 20_000),
            expiry: LocalDate(dayNumber: 20_030),
            cycleMonths: 1,
            money: Money(minorUnits: 1_200, currency: .cny),
            note: note,
            reminderEnabled: false
        )
    }

    private func subscriptionFields(
        _ input: SubscriptionCreateInput
    ) throws -> [String: SyncValue] {
        try SyncRecordPayload.subscription(
            SubscriptionRecord(
                input: input,
                now: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            sharing: input.sharing
        )
    }

    private func subscriptionChange(
        sourceChangeID: String,
        input: SubscriptionCreateInput,
        revision: Int64,
        baseRevision: Int64,
        changedFields: Set<String>,
        receivedAt: Date = Date(timeIntervalSince1970: 1_700_000_100)
    ) throws -> SyncRemoteChange {
        let fields = try subscriptionFields(input)
        return try remoteChange(
            sourceChangeID: sourceChangeID,
            envelope: CloudRecordEnvelope(
                recordType: .subscription,
                recordID: input.id.uuidString,
                revision: revision,
                modifiedAt: receivedAt,
                modifiedByDeviceID: UUID(),
                isDeleted: false,
                deletedAt: nil,
                fieldValues: fields,
                baseRevision: baseRevision,
                changedFields: changedFields,
                relationshipChanges: []
            ),
            receivedAt: receivedAt
        )
    }

    private func periodChange(
        sourceChangeID: String,
        input: SubscriptionPeriodCreateInput,
        revision: Int64,
        baseRevision: Int64,
        receivedAt: Date = Date(timeIntervalSince1970: 1_700_000_100)
    ) throws -> SyncRemoteChange {
        let fields = try SyncRecordPayload.period(
            SubscriptionPeriodRecord(
                input: input,
                now: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            sharing: input.sharing
        )
        return try remoteChange(
            sourceChangeID: sourceChangeID,
            envelope: CloudRecordEnvelope(
                recordType: .subscriptionPeriod,
                recordID: input.id.uuidString,
                revision: revision,
                modifiedAt: receivedAt,
                modifiedByDeviceID: UUID(),
                isDeleted: false,
                deletedAt: nil,
                fieldValues: fields,
                baseRevision: baseRevision,
                changedFields: Set(fields.keys),
                relationshipChanges: []
            ),
            receivedAt: receivedAt
        )
    }

    private func paymentChange(
        sourceChangeID: String,
        input: SubscriptionPaymentCreateInput,
        receivedAt: Date = Date(timeIntervalSince1970: 1_700_000_100)
    ) throws -> SyncRemoteChange {
        let fields = SyncRecordPayload.payment(
            SubscriptionPaymentRecord(
                input: input,
                now: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            attachmentReferences: input.attachmentReferences
        )
        return try remoteChange(
            sourceChangeID: sourceChangeID,
            envelope: CloudRecordEnvelope(
                recordType: .subscriptionPayment,
                recordID: input.id.uuidString,
                revision: 1,
                modifiedAt: receivedAt,
                modifiedByDeviceID: UUID(),
                isDeleted: false,
                deletedAt: nil,
                fieldValues: fields,
                baseRevision: 0,
                changedFields: Set(fields.keys),
                relationshipChanges: []
            ),
            receivedAt: receivedAt
        )
    }

    private func assetChange(
        sourceChangeID: String,
        reference: String,
        data: Data,
        receivedAt: Date
    ) throws -> SyncRemoteChange {
        let metadata = assetMetadata(for: data)
        let fields = SyncRecordPayload.iconAsset(
            reference: reference,
            metadata: metadata
        )
        let snapshot = SyncRecordSnapshot(
            recordType: .iconAsset,
            recordID: reference,
            revision: 1,
            modifiedAt: receivedAt,
            modifiedByDeviceID: UUID(),
            isDeleted: false,
            deletedAt: nil,
            fieldValues: fields,
            serverRecordData: nil
        )
        let assetURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(metadata.format.filenameExtension)
        try data.write(to: assetURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let record = try CloudRecordCodec.makeRecord(
            snapshot: snapshot,
            baseRevision: 0,
            changedFields: Set(fields.keys),
            relationshipChanges: [],
            zoneID: CKRecordZone.ID(zoneName: "Periodic"),
            assetFileURL: assetURL,
            assetMetadata: metadata
        )
        return SyncRemoteChange(
            sourceChangeID: sourceChangeID,
            envelope: try CloudRecordCodec.decode(record),
            serverRecordData: CloudRecordCodec.systemFieldsData(for: record),
            receivedAt: receivedAt
        )
    }

    private func remoteChange(
        sourceChangeID: String,
        envelope: CloudRecordEnvelope,
        receivedAt: Date
    ) throws -> SyncRemoteChange {
        let snapshot = SyncRecordSnapshot(
            recordType: envelope.recordType,
            recordID: envelope.recordID,
            revision: envelope.revision,
            modifiedAt: envelope.modifiedAt,
            modifiedByDeviceID: envelope.modifiedByDeviceID,
            isDeleted: envelope.isDeleted,
            deletedAt: envelope.deletedAt,
            fieldValues: envelope.fieldValues,
            serverRecordData: nil
        )
        let record = try CloudRecordCodec.makeRecord(
            snapshot: snapshot,
            baseRevision: envelope.baseRevision,
            changedFields: envelope.changedFields,
            relationshipChanges: envelope.relationshipChanges,
            zoneID: CKRecordZone.ID(zoneName: "Periodic")
        )
        return SyncRemoteChange(
            sourceChangeID: sourceChangeID,
            envelope: envelope,
            serverRecordData: CloudRecordCodec.systemFieldsData(for: record),
            receivedAt: receivedAt
        )
    }

    private func cloudImageData() throws -> Data {
        try #require(Data(base64Encoded: Self.onePixelPNG))
    }

    private func assetMetadata(for data: Data) -> CloudAssetMetadata {
        CloudAssetMetadata(
            contentHash: CloudImageAssetStager.contentHash(of: data),
            format: .png,
            byteCount: data.count
        )
    }

    @MainActor
    private func uploadChanges(
        container: ModelContainer,
        access: DatasetAccessCoordinator
    ) async throws -> [SyncRemoteChange] {
        let mutationStore = SyncMutationStore(
            modelContainer: container,
            datasetAccess: access
        )
        let mutations = try await mutationStore.fetchPending(limit: 5_000)
        let uploads = try SyncUploadBatchBuilder.build(
            mutations: mutations,
            snapshots: try await SyncRecordSnapshotStore(
                modelContainer: container,
                datasetAccess: access
            ).snapshots(for: mutations)
        )
        let zoneID = CKRecordZone.ID(zoneName: "Periodic")
        return try uploads.enumerated().map { index, upload in
            let record = try CloudRecordCodec.makeRecord(
                upload: upload,
                zoneID: zoneID
            )
            return SyncRemoteChange(
                sourceChangeID: "multi-\(index)",
                envelope: try CloudRecordCodec.decode(record),
                serverRecordData: CloudRecordCodec.systemFieldsData(
                    for: record
                ),
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    .addingTimeInterval(TimeInterval(index))
            )
        }
    }

    @MainActor
    private func uploadChange(
        sourceChangeID: String,
        container: ModelContainer,
        access: DatasetAccessCoordinator,
        acknowledgesMutations: Bool = false
    ) async throws -> SyncRemoteChange {
        let mutationStore = SyncMutationStore(
            modelContainer: container,
            datasetAccess: access
        )
        let mutations = try await mutationStore.fetchPending()
        let snapshots = try await SyncRecordSnapshotStore(
            modelContainer: container,
            datasetAccess: access
        ).snapshots(for: mutations)
        let upload = try #require(
            SyncUploadBatchBuilder.build(
                mutations: mutations,
                snapshots: snapshots
            ).first
        )
        let record = try CloudRecordCodec.makeRecord(
            upload: upload,
            zoneID: CKRecordZone.ID(zoneName: "Periodic")
        )
        let serverRecordData = CloudRecordCodec.systemFieldsData(for: record)
        if acknowledgesMutations {
            let mutationIDs = Set(upload.mutationIDs)
            try await mutationStore.markUploading(mutationIDs)
            try await SyncRecordSnapshotStore(
                modelContainer: container,
                datasetAccess: access
            ).updateServerRecordData(
                serverRecordData,
                recordType: upload.snapshot.recordType,
                recordID: upload.snapshot.recordID
            )
            try await mutationStore.markAcknowledged(mutationIDs)
            _ = try await mutationStore.removeAcknowledged()
        }
        return SyncRemoteChange(
            sourceChangeID: sourceChangeID,
            envelope: try CloudRecordCodec.decode(record),
            serverRecordData: serverRecordData,
            receivedAt: .now
        )
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
