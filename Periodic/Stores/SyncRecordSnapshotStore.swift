import Foundation
import SwiftData

@ModelActor
actor SyncRecordSnapshotStore {
    enum StoreError: LocalizedError, Equatable {
        case invalidRecordID
        case recordStateNotFound
        case recordNotFound
        case invalidStoredValue(String)

        var errorDescription: String? {
            switch self {
            case .invalidRecordID:
                "同步记录标识无效。"
            case .recordStateNotFound:
                "同步记录状态不存在。"
            case .recordNotFound:
                "同步记录正文不存在，且没有删除墓碑。"
            case .invalidStoredValue(let field):
                "同步记录的 \(field) 字段无法识别。"
            }
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

    func snapshot(
        recordType: SyncRecordType,
        recordID: String
    ) async throws -> SyncRecordSnapshot {
        let state = try fetchState(
            recordType: recordType,
            recordID: recordID
        )
        let fieldValues: [String: SyncValue]
        if state.isDeleted {
            fieldValues = [:]
        } else {
            fieldValues = try await payload(
                recordType: recordType,
                recordID: recordID
            )
        }
        return SyncRecordSnapshot(
            recordType: recordType,
            recordID: recordID,
            revision: state.revision,
            modifiedAt: state.modifiedAt,
            modifiedByDeviceID: state.modifiedByDeviceID,
            isDeleted: state.isDeleted,
            deletedAt: state.deletedAt,
            fieldValues: fieldValues,
            serverRecordData: state.serverRecordData
        )
    }

    func snapshots(
        for mutations: [SyncMutation]
    ) async throws -> [SyncRecordSnapshot] {
        let identities = Set(
            mutations.map {
                RecordIdentity(recordType: $0.recordType, recordID: $0.recordID)
            }
        )
        var snapshots: [SyncRecordSnapshot] = []
        let orderedIdentities = identities.sorted {
            ($0.recordType.rawValue, $0.recordID)
                < ($1.recordType.rawValue, $1.recordID)
        }
        for identity in orderedIdentities {
            snapshots.append(
                try await snapshot(
                    recordType: identity.recordType,
                    recordID: identity.recordID
                )
            )
        }
        return snapshots
    }

    func updateServerRecordData(
        _ data: Data?,
        recordType: SyncRecordType,
        recordID: String
    ) async throws {
        let lease = try await datasetAccess.acquireWrite()
        do {
            let state = try fetchState(
                recordType: recordType,
                recordID: recordID
            )
            state.serverRecordData = data
            try modelContext.save()
            await datasetAccess.releaseWrite(lease)
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    private func payload(
        recordType: SyncRecordType,
        recordID: String
    ) async throws -> [String: SyncValue] {
        switch recordType {
        case .subscription:
            let id = try uuid(recordID)
            let record = try fetchOne(
                FetchDescriptor<SubscriptionRecord>(
                    predicate: #Predicate { $0.id == id }
                )
            )
            let sharing = try SubscriptionSharingPersistence(context: modelContext)
                .plan(subscriptionID: id)
            return try SyncRecordPayload.subscription(record, sharing: sharing)
        case .subscriptionPeriod:
            let id = try uuid(recordID)
            let record = try fetchOne(
                FetchDescriptor<SubscriptionPeriodRecord>(
                    predicate: #Predicate { $0.id == id }
                )
            )
            let sharing = try SubscriptionSharingPersistence(context: modelContext)
                .plan(
                    subscriptionID: record.subscriptionID,
                    periodID: record.id
                )
            return try SyncRecordPayload.period(record, sharing: sharing)
        case .subscriptionPayment:
            let id = try uuid(recordID)
            let record = try fetchOne(
                FetchDescriptor<SubscriptionPaymentRecord>(
                    predicate: #Predicate { $0.id == id }
                )
            )
            return SyncRecordPayload.payment(
                record,
                attachmentReferences: try paymentAttachmentReferences(
                    paymentID: id
                )
            )
        case .serviceTemplate:
            let id = try uuid(recordID)
            return try SyncRecordPayload.template(
                fetchOne(
                    FetchDescriptor<ServiceTemplateRecord>(
                        predicate: #Predicate { $0.id == id }
                    )
                )
            )
        case .templateCategory:
            let id = try uuid(recordID)
            return SyncRecordPayload.category(
                try fetchOne(
                    FetchDescriptor<TemplateCategoryRecord>(
                        predicate: #Predicate { $0.id == id }
                    )
                )
            )
        case .builtinTemplateCategoryAssignment:
            let key = recordID
            return SyncRecordPayload.builtinCategoryAssignment(
                try fetchOne(
                    FetchDescriptor<BuiltinTemplateCategoryAssignmentRecord>(
                        predicate: #Predicate { $0.templateKey == key }
                    )
                )
            )
        case .iconAsset:
            guard CloudAssetRepository.isSupportedReference(recordID),
                  let assetRepository else {
                throw StoreError.invalidStoredValue("iconAsset")
            }
            return SyncRecordPayload.iconAsset(
                reference: recordID,
                metadata: try await assetRepository.metadata(
                    reference: recordID
                )
            )
        }
    }

    private func fetchState(
        recordType: SyncRecordType,
        recordID: String
    ) throws -> SyncRecordStateRecord {
        guard let record = try fetchStateIfPresent(
            recordType: recordType,
            recordID: recordID
        ) else {
            throw StoreError.recordStateNotFound
        }
        return record
    }

    private func fetchStateIfPresent(
        recordType: SyncRecordType,
        recordID: String
    ) throws -> SyncRecordStateRecord? {
        let recordKey = SyncRecordStateRecord.key(
            recordType: recordType,
            recordID: recordID
        )
        var descriptor = FetchDescriptor<SyncRecordStateRecord>(
            predicate: #Predicate { $0.recordKey == recordKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchOne<Record: PersistentModel>(
        _ descriptor: FetchDescriptor<Record>
    ) throws -> Record {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw StoreError.recordNotFound
        }
        return record
    }

    private func paymentAttachmentReferences(
        paymentID: UUID
    ) throws -> [String] {
        let current = try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>(
                predicate: #Predicate { $0.paymentID == paymentID },
                sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
            )
        ).map(\.reference)
        guard current.isEmpty else { return current }
        return try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentRecord>(
                predicate: #Predicate { $0.paymentID == paymentID }
            )
        ).map(\.reference)
    }

    private func uuid(_ rawValue: String) throws -> UUID {
        guard let value = UUID(uuidString: rawValue) else {
            throw StoreError.invalidRecordID
        }
        return value
    }

    private struct RecordIdentity: Hashable {
        let recordType: SyncRecordType
        let recordID: String
    }
}
