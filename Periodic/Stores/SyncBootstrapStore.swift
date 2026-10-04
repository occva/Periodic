import Foundation
import SwiftData

struct SyncBootstrapReceipt: Equatable, Sendable {
    let createdMutationCount: Int
}

@ModelActor
actor SyncBootstrapStore {
    enum BootstrapError: LocalizedError, Equatable {
        case assetRepositoryUnavailable

        var errorDescription: String? {
            "iCloud 图片存储尚未准备完成。"
        }
    }

    private var datasetAccess = DatasetAccessCoordinator()
    private var assetRepository: CloudAssetRepository?

    init(
        modelContainer: ModelContainer,
        datasetAccess: DatasetAccessCoordinator = DatasetAccessCoordinator(),
        assetRepository: CloudAssetRepository? = nil
    ) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.datasetAccess = datasetAccess
        self.assetRepository = assetRepository
    }

    func bootstrapExistingRecords() async throws -> SyncBootstrapReceipt {
        let maintenance = try await datasetAccess.beginMaintenance()
        do {
            let existingKeys = Set(
                try modelContext.fetch(FetchDescriptor<SyncRecordStateRecord>())
                    .map(\.recordKey)
            )
            var createdCount = 0
            let sharingPersistence = SubscriptionSharingPersistence(
                context: modelContext
            )

            for record in try modelContext.fetch(
                FetchDescriptor<SubscriptionRecord>()
            ) where !existingKeys.contains(
                SyncRecordStateRecord.key(
                    recordType: .subscription,
                    recordID: record.id.uuidString
                )
            ) {
                try SyncMutationJournal.recordCreate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscription,
                    recordID: record.id.uuidString,
                    fieldValues: try SyncRecordPayload.subscription(
                        record,
                        sharing: sharingPersistence.plan(
                            subscriptionID: record.id
                        )
                    )
                )
                createdCount += 1
            }

            for record in try modelContext.fetch(
                FetchDescriptor<SubscriptionPeriodRecord>()
            ) where !existingKeys.contains(
                SyncRecordStateRecord.key(
                    recordType: .subscriptionPeriod,
                    recordID: record.id.uuidString
                )
            ) {
                try SyncMutationJournal.recordCreate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscriptionPeriod,
                    recordID: record.id.uuidString,
                    fieldValues: try SyncRecordPayload.period(
                        record,
                        sharing: sharingPersistence.plan(
                            subscriptionID: record.subscriptionID,
                            periodID: record.id
                        )
                    )
                )
                createdCount += 1
            }

            let attachmentReferences = try paymentAttachmentReferencesByPaymentID()
            for record in try modelContext.fetch(
                FetchDescriptor<SubscriptionPaymentRecord>()
            ) where !existingKeys.contains(
                SyncRecordStateRecord.key(
                    recordType: .subscriptionPayment,
                    recordID: record.id.uuidString
                )
            ) {
                try SyncMutationJournal.recordCreate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscriptionPayment,
                    recordID: record.id.uuidString,
                    fieldValues: SyncRecordPayload.payment(
                        record,
                        attachmentReferences: attachmentReferences[record.id] ?? []
                    )
                )
                createdCount += 1
            }

            for record in try modelContext.fetch(
                FetchDescriptor<ServiceTemplateRecord>()
            ) where !existingKeys.contains(
                SyncRecordStateRecord.key(
                    recordType: .serviceTemplate,
                    recordID: record.id.uuidString
                )
            ) {
                try SyncMutationJournal.recordCreate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .serviceTemplate,
                    recordID: record.id.uuidString,
                    fieldValues: try SyncRecordPayload.template(record)
                )
                createdCount += 1
            }

            for record in try modelContext.fetch(
                FetchDescriptor<TemplateCategoryRecord>()
            ) where !existingKeys.contains(
                SyncRecordStateRecord.key(
                    recordType: .templateCategory,
                    recordID: record.id.uuidString
                )
            ) {
                try SyncMutationJournal.recordCreate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .templateCategory,
                    recordID: record.id.uuidString,
                    fieldValues: SyncRecordPayload.category(record)
                )
                createdCount += 1
            }

            for record in try modelContext.fetch(
                FetchDescriptor<BuiltinTemplateCategoryAssignmentRecord>()
            ) where !existingKeys.contains(
                SyncRecordStateRecord.key(
                    recordType: .builtinTemplateCategoryAssignment,
                    recordID: record.templateKey
                )
            ) {
                try SyncMutationJournal.recordCreate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .builtinTemplateCategoryAssignment,
                    recordID: record.templateKey,
                    fieldValues: SyncRecordPayload
                        .builtinCategoryAssignment(record)
                )
                createdCount += 1
            }

            createdCount += try await bootstrapAssetRecords(
                existingKeys: existingKeys,
                paymentAttachmentReferences: attachmentReferences
            )

            if createdCount > 0 {
                try modelContext.save()
            }
            await datasetAccess.endMaintenance(maintenance)
            return SyncBootstrapReceipt(createdMutationCount: createdCount)
        } catch {
            modelContext.rollback()
            await datasetAccess.endMaintenance(maintenance)
            throw error
        }
    }

    func bootstrapAssetRecords() async throws -> SyncBootstrapReceipt {
        let lease = try await datasetAccess.acquireWrite()
        do {
            let existingKeys = Set(
                try modelContext.fetch(FetchDescriptor<SyncRecordStateRecord>())
                    .map(\.recordKey)
            )
            let createdCount = try await bootstrapAssetRecords(
                existingKeys: existingKeys,
                paymentAttachmentReferences:
                    paymentAttachmentReferencesByPaymentID()
            )
            if createdCount > 0 {
                try modelContext.save()
            }
            await datasetAccess.releaseWrite(lease)
            return SyncBootstrapReceipt(
                createdMutationCount: createdCount
            )
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    func recordAssetDeletions(
        references: Set<String>
    ) async throws -> SyncBootstrapReceipt {
        let references = references.filter(
            CloudAssetRepository.isSupportedReference
        )
        guard !references.isEmpty else {
            return SyncBootstrapReceipt(createdMutationCount: 0)
        }
        let lease = try await datasetAccess.acquireWrite()
        do {
            let recordTypeRaw = SyncRecordType.iconAsset.rawValue
            let states = try modelContext.fetch(
                FetchDescriptor<SyncRecordStateRecord>(
                    predicate: #Predicate {
                        $0.recordTypeRaw == recordTypeRaw
                    }
                )
            )
            var createdCount = 0
            for state in states
            where references.contains(state.recordID) && !state.isDeleted {
                try SyncMutationJournal.recordDelete(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .iconAsset,
                    recordID: state.recordID
                )
                createdCount += 1
            }
            if createdCount > 0 {
                try modelContext.save()
            }
            await datasetAccess.releaseWrite(lease)
            return SyncBootstrapReceipt(
                createdMutationCount: createdCount
            )
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    private func paymentAttachmentReferencesByPaymentID() throws -> [UUID: [String]] {
        let current = Dictionary(
            grouping: try modelContext.fetch(
                FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>()
            ),
            by: \.paymentID
        ).mapValues { records in
            records.sorted {
                ($0.sortOrder, $0.id.uuidString)
                    < ($1.sortOrder, $1.id.uuidString)
            }.map(\.reference)
        }
        return try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentRecord>()
        ).reduce(into: current) { result, record in
            if result[record.paymentID] == nil {
                result[record.paymentID] = [record.reference]
            }
        }
    }

    private func syncableAssetReferences(
        paymentAttachmentReferences: [UUID: [String]]
    ) throws -> [String] {
        let subscriptionReferences = try modelContext.fetch(
            FetchDescriptor<SubscriptionRecord>()
        ).compactMap(\.iconURLString)
        let templateReferences = try modelContext.fetch(
            FetchDescriptor<ServiceTemplateRecord>()
        ).compactMap(\.iconURLString)
        return Set(
            subscriptionReferences
                + templateReferences
                + paymentAttachmentReferences.values.flatMap { $0 }
        )
        .filter(CloudAssetRepository.isSupportedReference)
        .sorted()
    }

    private func bootstrapAssetRecords(
        existingKeys: Set<String>,
        paymentAttachmentReferences: [UUID: [String]]
    ) async throws -> Int {
        var createdCount = 0
        for reference in try syncableAssetReferences(
            paymentAttachmentReferences: paymentAttachmentReferences
        ) where !existingKeys.contains(
            SyncRecordStateRecord.key(
                recordType: .iconAsset,
                recordID: reference
            )
        ) {
            guard let assetRepository else {
                throw BootstrapError.assetRepositoryUnavailable
            }
            let metadata = try await assetRepository.metadata(
                reference: reference
            )
            try SyncMutationJournal.recordCreate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .iconAsset,
                recordID: reference,
                fieldValues: SyncRecordPayload.iconAsset(
                    reference: reference,
                    metadata: metadata
                )
            )
            createdCount += 1
        }
        return createdCount
    }
}
