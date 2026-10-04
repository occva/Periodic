import Foundation
import SwiftData

@ModelActor
actor SyncRemoteInboxStore {
    enum StoreError: LocalizedError, Equatable {
        case invalidSourceChangeID
        case invalidEnvelope
        case duplicateChangeMismatch

        var errorDescription: String? {
            switch self {
            case .invalidSourceChangeID:
                "iCloud 远端变更缺少稳定标识。"
            case .invalidEnvelope:
                "iCloud 远端变更内容无效。"
            case .duplicateChangeMismatch:
                "iCloud 返回了标识相同但内容不同的远端变更。"
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

    func enqueue(_ changes: [SyncRemoteChange]) async throws -> Int {
        guard !changes.isEmpty else { return 0 }
        let lease = try await datasetAccess.acquireWrite()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let existing = try modelContext.fetch(
                FetchDescriptor<SyncRemoteChangeRecord>()
            )
            var recordsByChangeID = Dictionary(
                uniqueKeysWithValues: existing.map { ($0.sourceChangeID, $0) }
            )
            var insertedCount = 0

            for change in changes {
                try validate(change)
                let envelopeData = try encoder.encode(change.envelope)
                if let stored = recordsByChangeID[change.sourceChangeID] {
                    guard stored.envelopeData == envelopeData,
                          stored.serverRecordData == change.serverRecordData else {
                        throw StoreError.duplicateChangeMismatch
                    }
                    continue
                }
                let record = SyncRemoteChangeRecord(
                    sourceChangeID: change.sourceChangeID,
                    envelope: change.envelope,
                    envelopeData: envelopeData,
                    serverRecordData: change.serverRecordData,
                    receivedAt: change.receivedAt
                )
                modelContext.insert(record)
                recordsByChangeID[change.sourceChangeID] = record
                insertedCount += 1
            }
            if insertedCount > 0 {
                try modelContext.save()
            }
            await datasetAccess.releaseWrite(lease)
            return insertedCount
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    func state(
        sourceChangeID: String
    ) throws -> SyncRemoteChangeState? {
        var descriptor = FetchDescriptor<SyncRemoteChangeRecord>(
            predicate: #Predicate {
                $0.sourceChangeID == sourceChangeID
            }
        )
        descriptor.fetchLimit = 1
        guard let rawValue = try modelContext.fetch(descriptor).first?
            .stateRaw else {
            return nil
        }
        guard let state = SyncRemoteChangeState(rawValue: rawValue) else {
            throw StoreError.invalidEnvelope
        }
        return state
    }

    private func validate(_ change: SyncRemoteChange) throws {
        guard !change.sourceChangeID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            throw StoreError.invalidSourceChangeID
        }
        let envelope = change.envelope
        guard !envelope.recordID.isEmpty,
              envelope.revision > 0,
              envelope.baseRevision >= 0,
              envelope.revision > envelope.baseRevision,
              !change.serverRecordData.isEmpty else {
            throw StoreError.invalidEnvelope
        }
        do {
            try CloudRecordCodec.validateSystemFieldsData(
                change.serverRecordData,
                envelope: envelope
            )
        } catch {
            throw StoreError.invalidEnvelope
        }
        if envelope.isDeleted {
            guard envelope.deletedAt != nil,
                  envelope.fieldValues.isEmpty,
                  envelope.changedFields.isEmpty else {
                throw StoreError.invalidEnvelope
            }
        } else {
            guard envelope.deletedAt == nil,
                  envelope.changedFields.isSubset(
                    of: Set(envelope.fieldValues.keys)
                  ) else {
                throw StoreError.invalidEnvelope
            }
        }
    }
}
