import Foundation
import SwiftData

@ModelActor
actor CloudSyncStatusStore {
    enum StoreError: LocalizedError {
        case invalidStoredValue(String)

        var errorDescription: String? {
            switch self {
            case .invalidStoredValue(let field):
                "同步状态的 \(field) 字段无法识别。"
            }
        }
    }

    func snapshot() throws -> CloudSyncQueueSnapshot {
        let mutations = try modelContext.fetch(
            FetchDescriptor<SyncMutationRecord>()
        )
        let pendingUploadCount = mutations.count {
            $0.stateRaw == SyncMutationState.pending.rawValue
                || $0.stateRaw == SyncMutationState.uploading.rawValue
        }
        let pendingDownloadCount = try modelContext.fetch(
            FetchDescriptor<SyncRemoteChangeRecord>()
        ).count {
            $0.stateRaw == SyncRemoteChangeState.pending.rawValue
        }
        let conflictCount = try modelContext.fetch(
            FetchDescriptor<SyncConflictRecord>()
        ).count {
            $0.stateRaw == SyncConflictState.unresolved.rawValue
        }
        return CloudSyncQueueSnapshot(
            pendingUploadCount: pendingUploadCount,
            pendingDownloadCount: pendingDownloadCount,
            conflictCount: conflictCount
        )
    }

    func unresolvedConflicts() throws -> [CloudSyncConflictSummary] {
        let unresolved = SyncConflictState.unresolved.rawValue
        return try modelContext.fetch(
            FetchDescriptor<SyncConflictRecord>(
                predicate: #Predicate {
                    $0.stateRaw == unresolved
                },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
        ).map { record in
            guard let recordType = SyncRecordType(
                rawValue: record.recordTypeRaw
            ) else {
                throw StoreError.invalidStoredValue(
                    "conflict.recordTypeRaw"
                )
            }
            let payload = try JSONDecoder().decode(
                SyncConflictPayload.self,
                from: record.payloadData
            )
            return CloudSyncConflictSummary(
                id: record.conflictID,
                recordType: recordType,
                recordID: record.recordID,
                fieldNames: conflictFields(payload),
                localValues: payload.localSnapshot.fieldValues,
                remoteValues: payload.remoteEnvelope.fieldValues,
                involvesDeletion:
                    payload.localSnapshot.isDeleted
                    || payload.remoteEnvelope.isDeleted,
                createdAt: record.createdAt
            )
        }
    }

    private func conflictFields(
        _ payload: SyncConflictPayload
    ) -> [String] {
        var fields = Set<String>()
        for reason in payload.reasons {
            switch reason {
            case .fields(let values),
                 .atomicFieldGroup(let values):
                fields.formUnion(values)
            case .divergentBaseRevision:
                fields.formUnion(payload.localChange.changedFields)
                fields.formUnion(payload.remoteEnvelope.changedFields)
            case .differentRecords,
                 .deletionVersusModification,
                 .relationships,
                 .revisionOverflow:
                break
            }
        }
        return fields.sorted()
    }
}
