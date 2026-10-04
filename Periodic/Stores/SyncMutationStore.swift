import Foundation
import SwiftData

@ModelActor
actor SyncMutationStore {
    enum StoreError: LocalizedError, Equatable {
        case invalidStoredValue(String)
        case mutationNotFound
        case invalidTransition(from: SyncMutationState, to: SyncMutationState)

        var errorDescription: String? {
            switch self {
            case .invalidStoredValue(let field):
                "同步队列的 \(field) 字段无法识别。"
            case .mutationNotFound:
                "待同步变更已不存在。"
            case .invalidTransition(let from, let to):
                "同步变更不能从 \(from.rawValue) 切换到 \(to.rawValue)。"
            }
        }
    }

    private var datasetAccess = DatasetAccessCoordinator()

    init(
        modelContainer: ModelContainer,
        datasetAccess: DatasetAccessCoordinator = DatasetAccessCoordinator()
    ) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.datasetAccess = datasetAccess
    }

    func fetchPending(limit: Int = 200) throws -> [SyncMutation] {
        guard limit > 0 else { return [] }
        let pending = SyncMutationState.pending.rawValue
        var descriptor = FetchDescriptor<SyncMutationRecord>(
            predicate: #Predicate { $0.stateRaw == pending },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(makeMutation)
    }

    func markUploading(_ mutationIDs: Set<UUID>) async throws {
        try await transition(
            mutationIDs,
            allowedSources: [.pending],
            target: .uploading
        )
    }

    func markPending(_ mutationIDs: Set<UUID>) async throws {
        try await transition(
            mutationIDs,
            allowedSources: [.uploading],
            target: .pending
        )
    }

    func markAcknowledged(_ mutationIDs: Set<UUID>) async throws {
        try await transition(
            mutationIDs,
            allowedSources: [.uploading],
            target: .acknowledged
        )
    }

    func markConflicted(_ mutationIDs: Set<UUID>) async throws {
        try await transition(
            mutationIDs,
            allowedSources: [.uploading],
            target: .conflicted
        )
    }

    func retryConflicted(_ mutationIDs: Set<UUID>) async throws {
        try await transition(
            mutationIDs,
            allowedSources: [.conflicted],
            target: .pending
        )
    }

    func acknowledgeUpload(
        mutationIDs: Set<UUID>,
        recordType: SyncRecordType,
        recordID: String,
        serverRecordData: Data
    ) async throws {
        guard !mutationIDs.isEmpty else { return }
        let lease = try await datasetAccess.acquireWrite()
        do {
            let ids = Array(mutationIDs)
            let records = try modelContext.fetch(
                FetchDescriptor<SyncMutationRecord>(
                    predicate: #Predicate { ids.contains($0.mutationID) }
                )
            )
            guard records.count == mutationIDs.count else {
                throw StoreError.mutationNotFound
            }
            for record in records {
                guard let source = SyncMutationState(
                    rawValue: record.stateRaw
                ) else {
                    throw StoreError.invalidStoredValue("stateRaw")
                }
                guard source == .pending || source == .uploading else {
                    throw StoreError.invalidTransition(
                        from: source,
                        to: .acknowledged
                    )
                }
            }
            let recordKey = SyncRecordStateRecord.key(
                recordType: recordType,
                recordID: recordID
            )
            var stateDescriptor = FetchDescriptor<SyncRecordStateRecord>(
                predicate: #Predicate { $0.recordKey == recordKey }
            )
            stateDescriptor.fetchLimit = 1
            guard let state = try modelContext.fetch(stateDescriptor).first
            else {
                throw StoreError.invalidStoredValue("recordState")
            }
            state.serverRecordData = serverRecordData
            records.forEach(modelContext.delete)
            try modelContext.save()
            await datasetAccess.releaseWrite(lease)
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    func removeAcknowledged() async throws -> Int {
        let lease = try await datasetAccess.acquireWrite()
        do {
            let acknowledged = SyncMutationState.acknowledged.rawValue
            let records = try modelContext.fetch(
                FetchDescriptor<SyncMutationRecord>(
                    predicate: #Predicate { $0.stateRaw == acknowledged }
                )
            )
            records.forEach(modelContext.delete)
            if !records.isEmpty {
                try modelContext.save()
            }
            await datasetAccess.releaseWrite(lease)
            return records.count
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    private func transition(
        _ mutationIDs: Set<UUID>,
        allowedSources: Set<SyncMutationState>,
        target: SyncMutationState
    ) async throws {
        guard !mutationIDs.isEmpty else { return }
        let lease = try await datasetAccess.acquireWrite()
        do {
            let ids = Array(mutationIDs)
            let records = try modelContext.fetch(
                FetchDescriptor<SyncMutationRecord>(
                    predicate: #Predicate { ids.contains($0.mutationID) }
                )
            )
            guard records.count == mutationIDs.count else {
                throw StoreError.mutationNotFound
            }
            for record in records {
                guard let source = SyncMutationState(rawValue: record.stateRaw) else {
                    throw StoreError.invalidStoredValue("stateRaw")
                }
                guard allowedSources.contains(source) else {
                    throw StoreError.invalidTransition(from: source, to: target)
                }
                record.stateRaw = target.rawValue
                record.updatedAt = .now
            }
            try modelContext.save()
            await datasetAccess.releaseWrite(lease)
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    private func makeMutation(_ record: SyncMutationRecord) throws -> SyncMutation {
        guard let recordType = SyncRecordType(rawValue: record.recordTypeRaw) else {
            throw StoreError.invalidStoredValue("recordTypeRaw")
        }
        guard let operation = SyncMutationOperation(rawValue: record.operationRaw) else {
            throw StoreError.invalidStoredValue("operationRaw")
        }
        guard let state = SyncMutationState(rawValue: record.stateRaw) else {
            throw StoreError.invalidStoredValue("stateRaw")
        }
        return SyncMutation(
            mutationID: record.mutationID,
            recordType: recordType,
            recordID: record.recordID,
            baseRevision: record.baseRevision,
            targetRevision: record.targetRevision,
            operation: operation,
            state: state,
            fieldValues: try SyncMutationJournal.fieldValues(from: record),
            relationshipChanges: try SyncMutationJournal.relationshipChanges(
                from: record
            ),
            deviceID: record.deviceID,
            createdAt: record.createdAt
        )
    }
}
