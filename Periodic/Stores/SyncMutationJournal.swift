import Foundation
import SwiftData

enum SyncMutationJournal {
    @discardableResult
    static func recordCreate(
        in context: ModelContext,
        deviceID: UUID,
        recordType: SyncRecordType,
        recordID: String,
        fieldValues: [String: SyncValue],
        relationshipChanges: Set<SyncRelationshipChange> = [],
        now: Date = Date()
    ) throws -> SyncMutationRecord {
        guard try state(
            in: context,
            recordType: recordType,
            recordID: recordID
        ) == nil else {
            throw SyncMutationJournalError.recordAlreadyTracked
        }
        let targetRevision: Int64 = 1
        let state = SyncRecordStateRecord(
            recordType: recordType,
            recordID: recordID,
            revision: targetRevision,
            modifiedAt: now,
            modifiedByDeviceID: deviceID,
            isDeleted: false,
            deletedAt: nil
        )
        context.insert(state)
        return try insertMutation(
            in: context,
            deviceID: deviceID,
            recordType: recordType,
            recordID: recordID,
            baseRevision: 0,
            targetRevision: targetRevision,
            operation: .create,
            fieldValues: fieldValues,
            relationshipChanges: relationshipChanges,
            now: now
        )
    }

    @discardableResult
    static func recordUpdate(
        in context: ModelContext,
        deviceID: UUID,
        recordType: SyncRecordType,
        recordID: String,
        previous: [String: SyncValue],
        current: [String: SyncValue],
        relationshipChanges: Set<SyncRelationshipChange> = [],
        legacyBaseRevision: Int64 = 1,
        now: Date = Date()
    ) throws -> SyncMutationRecord? {
        let changedValues = current.filter { key, value in
            previous[key] != value
        }
        guard !changedValues.isEmpty || !relationshipChanges.isEmpty else {
            return nil
        }

        let state = try stateOrCreate(
            in: context,
            deviceID: deviceID,
            recordType: recordType,
            recordID: recordID,
            legacyRevision: legacyBaseRevision,
            now: now
        )
        guard !state.isDeleted else {
            throw SyncMutationJournalError.cannotModifyDeletedRecord
        }
        let baseRevision = state.revision
        let targetRevision = try nextRevision(after: baseRevision)
        state.revision = targetRevision
        state.modifiedAt = now
        state.modifiedByDeviceID = deviceID
        return try insertMutation(
            in: context,
            deviceID: deviceID,
            recordType: recordType,
            recordID: recordID,
            baseRevision: baseRevision,
            targetRevision: targetRevision,
            operation: .update,
            fieldValues: changedValues,
            relationshipChanges: relationshipChanges,
            now: now
        )
    }

    @discardableResult
    static func recordDelete(
        in context: ModelContext,
        deviceID: UUID,
        recordType: SyncRecordType,
        recordID: String,
        legacyBaseRevision: Int64 = 1,
        relationshipChanges: Set<SyncRelationshipChange> = [],
        now: Date = Date()
    ) throws -> SyncMutationRecord {
        let state = try stateOrCreate(
            in: context,
            deviceID: deviceID,
            recordType: recordType,
            recordID: recordID,
            legacyRevision: legacyBaseRevision,
            now: now
        )
        guard !state.isDeleted else {
            throw SyncMutationJournalError.recordAlreadyDeleted
        }
        let baseRevision = state.revision
        let targetRevision = try nextRevision(after: baseRevision)
        state.revision = targetRevision
        state.modifiedAt = now
        state.modifiedByDeviceID = deviceID
        state.isDeleted = true
        state.deletedAt = now
        return try insertMutation(
            in: context,
            deviceID: deviceID,
            recordType: recordType,
            recordID: recordID,
            baseRevision: baseRevision,
            targetRevision: targetRevision,
            operation: .delete,
            fieldValues: [:],
            relationshipChanges: relationshipChanges,
            now: now
        )
    }

    static func pendingMutations(
        in context: ModelContext
    ) throws -> [SyncMutationRecord] {
        let pending = SyncMutationState.pending.rawValue
        return try context.fetch(
            FetchDescriptor<SyncMutationRecord>(
                predicate: #Predicate { $0.stateRaw == pending },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
        )
    }

    @discardableResult
    static func recordRebasedUpdate(
        in context: ModelContext,
        deviceID: UUID,
        recordType: SyncRecordType,
        recordID: String,
        baseRevision: Int64,
        targetRevision: Int64,
        fieldValues: [String: SyncValue],
        relationshipChanges: Set<SyncRelationshipChange>,
        now: Date = Date()
    ) throws -> SyncMutationRecord {
        guard targetRevision > baseRevision else {
            throw SyncMutationJournalError.invalidRevisionRange
        }
        guard let state = try state(
            in: context,
            recordType: recordType,
            recordID: recordID
        ), state.revision == targetRevision, !state.isDeleted else {
            throw SyncMutationJournalError.invalidRebasedState
        }
        return try insertMutation(
            in: context,
            deviceID: deviceID,
            recordType: recordType,
            recordID: recordID,
            baseRevision: baseRevision,
            targetRevision: targetRevision,
            operation: .update,
            fieldValues: fieldValues,
            relationshipChanges: relationshipChanges,
            now: now
        )
    }

    static func changedFields(
        from mutation: SyncMutationRecord
    ) throws -> Set<String> {
        try Set(JSONDecoder().decode([String].self, from: mutation.changedFieldsData))
    }

    static func fieldValues(
        from mutation: SyncMutationRecord
    ) throws -> [String: SyncValue] {
        try JSONDecoder().decode(
            [String: SyncValue].self,
            from: mutation.fieldValuesData
        )
    }

    static func relationshipChanges(
        from mutation: SyncMutationRecord
    ) throws -> Set<SyncRelationshipChange> {
        try Set(
            JSONDecoder().decode(
                [SyncRelationshipChange].self,
                from: mutation.relationshipChangesData
            )
        )
    }

    private static func insertMutation(
        in context: ModelContext,
        deviceID: UUID,
        recordType: SyncRecordType,
        recordID: String,
        baseRevision: Int64,
        targetRevision: Int64,
        operation: SyncMutationOperation,
        fieldValues: [String: SyncValue],
        relationshipChanges: Set<SyncRelationshipChange>,
        now: Date
    ) throws -> SyncMutationRecord {
        let encoder = JSONEncoder()
        let mutation = SyncMutationRecord(
            recordType: recordType,
            recordID: recordID,
            baseRevision: baseRevision,
            targetRevision: targetRevision,
            changedFieldsData: try encoder.encode(fieldValues.keys.sorted()),
            fieldValuesData: try encoder.encode(fieldValues),
            relationshipChangesData: try encoder.encode(
                relationshipChanges.sorted(by: relationshipSort)
            ),
            operation: operation,
            deviceID: deviceID,
            now: now
        )
        context.insert(mutation)
        return mutation
    }

    private static func stateOrCreate(
        in context: ModelContext,
        deviceID: UUID,
        recordType: SyncRecordType,
        recordID: String,
        legacyRevision: Int64,
        now: Date
    ) throws -> SyncRecordStateRecord {
        if let existing = try state(
            in: context,
            recordType: recordType,
            recordID: recordID
        ) {
            return existing
        }
        let record = SyncRecordStateRecord(
            recordType: recordType,
            recordID: recordID,
            revision: max(legacyRevision, 1),
            modifiedAt: now,
            modifiedByDeviceID: deviceID,
            isDeleted: false,
            deletedAt: nil
        )
        context.insert(record)
        return record
    }

    private static func state(
        in context: ModelContext,
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
        descriptor.fetchLimit = 2
        let records = try context.fetch(descriptor)
        guard records.count <= 1 else {
            throw SyncMutationJournalError.duplicateRecordState
        }
        return records.first
    }

    private static func nextRevision(after revision: Int64) throws -> Int64 {
        let (next, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else {
            throw SyncMutationJournalError.revisionOverflow
        }
        return next
    }

    private static func relationshipSort(
        _ lhs: SyncRelationshipChange,
        _ rhs: SyncRelationshipChange
    ) -> Bool {
        (
            lhs.relationship,
            lhs.relatedRecordType.rawValue,
            lhs.relatedRecordID,
            lhs.operation.rawValue
        ) < (
            rhs.relationship,
            rhs.relatedRecordType.rawValue,
            rhs.relatedRecordID,
            rhs.operation.rawValue
        )
    }
}

enum SyncMutationJournalError: LocalizedError, Equatable {
    case recordAlreadyTracked
    case recordAlreadyDeleted
    case cannotModifyDeletedRecord
    case duplicateRecordState
    case revisionOverflow
    case invalidRevisionRange
    case invalidRebasedState

    var errorDescription: String? {
        switch self {
        case .recordAlreadyTracked:
            "同步记录标识已存在，无法重复创建。"
        case .recordAlreadyDeleted:
            "这条同步记录已经删除。"
        case .cannotModifyDeletedRecord:
            "这条记录已在另一项操作中删除，不能继续修改。"
        case .duplicateRecordState:
            "数据库包含重复的同步记录状态，已停止写入。"
        case .revisionOverflow:
            "同步记录版本已达到上限，无法继续写入。"
        case .invalidRevisionRange:
            "合并后的同步记录版本无效。"
        case .invalidRebasedState:
            "合并后的同步记录状态与待上传变更不一致。"
        }
    }
}
