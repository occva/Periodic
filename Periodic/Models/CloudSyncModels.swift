import Foundation

enum SyncRecordType: String, Codable, CaseIterable, Sendable {
    case subscription
    case subscriptionPeriod
    case subscriptionPayment
    case serviceTemplate
    case templateCategory
    case builtinTemplateCategoryAssignment
    case iconAsset
}

enum SyncMutationOperation: String, Codable, Sendable {
    case create
    case update
    case delete
}

enum SyncMutationState: String, Codable, Sendable {
    case pending
    case uploading
    case acknowledged
    case conflicted
}

struct SyncMutation: Identifiable, Equatable, Sendable {
    var id: UUID { mutationID }

    let mutationID: UUID
    let recordType: SyncRecordType
    let recordID: String
    let baseRevision: Int64
    let targetRevision: Int64
    let operation: SyncMutationOperation
    let state: SyncMutationState
    let fieldValues: [String: SyncValue]
    let relationshipChanges: Set<SyncRelationshipChange>
    let deviceID: UUID
    let createdAt: Date
}

struct SyncRecordSnapshot: Codable, Equatable, Sendable {
    let recordType: SyncRecordType
    let recordID: String
    let revision: Int64
    let modifiedAt: Date
    let modifiedByDeviceID: UUID
    let isDeleted: Bool
    let deletedAt: Date?
    let fieldValues: [String: SyncValue]
    let serverRecordData: Data?
}

struct SyncUploadRecord: Equatable, Sendable {
    let snapshot: SyncRecordSnapshot
    let baseRevision: Int64
    let changedFields: Set<String>
    let relationshipChanges: Set<SyncRelationshipChange>
    let mutationIDs: [UUID]
}

enum SyncUploadBatchBuilder {
    enum BuildError: LocalizedError, Equatable {
        case missingSnapshot
        case nonContiguousRevision
        case snapshotRevisionMismatch
        case inconsistentDeletion

        var errorDescription: String? {
            switch self {
            case .missingSnapshot:
                "同步队列缺少当前记录快照。"
            case .nonContiguousRevision:
                "同步队列包含不连续的记录版本。"
            case .snapshotRevisionMismatch:
                "同步队列版本与当前记录不一致。"
            case .inconsistentDeletion:
                "同步队列的删除状态与当前记录不一致。"
            }
        }
    }

    static func build(
        mutations: [SyncMutation],
        snapshots: [SyncRecordSnapshot]
    ) throws -> [SyncUploadRecord] {
        let snapshotsByIdentity = Dictionary(
            uniqueKeysWithValues: snapshots.map {
                (RecordIdentity($0.recordType, $0.recordID), $0)
            }
        )
        let grouped = Dictionary(
            grouping: mutations,
            by: { RecordIdentity($0.recordType, $0.recordID) }
        )
        return try grouped.keys.sorted().map { identity in
            guard let snapshot = snapshotsByIdentity[identity] else {
                throw BuildError.missingSnapshot
            }
            let ordered = grouped[identity, default: []].sorted {
                ($0.targetRevision, $0.createdAt, $0.mutationID.uuidString)
                    < ($1.targetRevision, $1.createdAt, $1.mutationID.uuidString)
            }
            guard let first = ordered.first, let last = ordered.last else {
                throw BuildError.nonContiguousRevision
            }
            var expectedBase = first.baseRevision
            for (index, mutation) in ordered.enumerated() {
                guard mutation.baseRevision == expectedBase,
                      mutation.targetRevision > mutation.baseRevision else {
                    throw BuildError.nonContiguousRevision
                }
                if index > 0,
                   mutation.targetRevision != mutation.baseRevision + 1 {
                    throw BuildError.nonContiguousRevision
                }
                expectedBase = mutation.targetRevision
            }
            guard snapshot.revision == last.targetRevision else {
                throw BuildError.snapshotRevisionMismatch
            }
            guard snapshot.isDeleted == (last.operation == .delete) else {
                throw BuildError.inconsistentDeletion
            }
            let changedFields: Set<String>
            let relationshipChanges: Set<SyncRelationshipChange>
            if snapshot.isDeleted {
                changedFields = []
                relationshipChanges = []
            } else {
                changedFields = ordered.reduce(into: Set<String>()) {
                    $0.formUnion($1.fieldValues.keys)
                }
                relationshipChanges = collapsedRelationships(ordered)
            }
            return SyncUploadRecord(
                snapshot: snapshot,
                baseRevision: first.baseRevision,
                changedFields: changedFields,
                relationshipChanges: relationshipChanges,
                mutationIDs: ordered.map(\.mutationID)
            )
        }
    }

    private static func collapsedRelationships(
        _ mutations: [SyncMutation]
    ) -> Set<SyncRelationshipChange> {
        var latest: [RelationshipIdentity: SyncRelationshipChange] = [:]
        for mutation in mutations {
            for change in mutation.relationshipChanges {
                latest[RelationshipIdentity(change)] = change
            }
        }
        return Set(latest.values)
    }

    private struct RecordIdentity: Hashable, Comparable {
        let recordType: SyncRecordType
        let recordID: String

        init(_ recordType: SyncRecordType, _ recordID: String) {
            self.recordType = recordType
            self.recordID = recordID
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.recordType.rawValue, lhs.recordID)
                < (rhs.recordType.rawValue, rhs.recordID)
        }
    }

    private struct RelationshipIdentity: Hashable {
        let relationship: String
        let relatedRecordType: SyncRecordType
        let relatedRecordID: String

        init(_ change: SyncRelationshipChange) {
            relationship = change.relationship
            relatedRecordType = change.relatedRecordType
            relatedRecordID = change.relatedRecordID
        }
    }
}

enum SyncRelationshipOperation: String, Codable, Sendable {
    case add
    case remove
    case delete
}

struct SyncRelationshipChange: Codable, Hashable, Sendable {
    let operation: SyncRelationshipOperation
    let relationship: String
    let relatedRecordType: SyncRecordType
    let relatedRecordID: String
}

indirect enum SyncValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case string(String)
    case date(Date)
    case data(Data)
    case array([SyncValue])
    case object([String: SyncValue])
}

struct SyncChangeSet: Codable, Equatable, Sendable {
    let recordType: SyncRecordType
    let recordID: String
    let baseRevision: Int64
    let targetRevision: Int64
    let operation: SyncMutationOperation
    let fieldValues: [String: SyncValue]
    let relationshipChanges: Set<SyncRelationshipChange>

    var changedFields: Set<String> {
        Set(fieldValues.keys)
    }
}

enum SyncMergeConflictReason: Codable, Equatable, Sendable {
    case differentRecords
    case divergentBaseRevision(local: Int64, remote: Int64)
    case deletionVersusModification
    case fields(Set<String>)
    case atomicFieldGroup(Set<String>)
    case relationships(Set<SyncRelationshipChange>)
    case revisionOverflow
}

struct SyncMergeConflict: Equatable, Sendable {
    let local: SyncChangeSet
    let remote: SyncChangeSet
    let reasons: [SyncMergeConflictReason]
}

struct CloudRecordEnvelope: Codable, Equatable, Sendable {
    let recordType: SyncRecordType
    let recordID: String
    let revision: Int64
    let modifiedAt: Date
    let modifiedByDeviceID: UUID
    let isDeleted: Bool
    let deletedAt: Date?
    let fieldValues: [String: SyncValue]
    let baseRevision: Int64
    let changedFields: Set<String>
    let relationshipChanges: Set<SyncRelationshipChange>

    var changeSet: SyncChangeSet {
        SyncChangeSet(
            recordType: recordType,
            recordID: recordID,
            baseRevision: baseRevision,
            targetRevision: revision,
            operation: isDeleted ? .delete : (baseRevision == 0 ? .create : .update),
            fieldValues: fieldValues.filter { changedFields.contains($0.key) },
            relationshipChanges: relationshipChanges
        )
    }
}

enum SyncRemoteChangeState: String, Codable, Sendable {
    case pending
    case applied
    case conflicted
    case failed
}

struct SyncRemoteChange: Equatable, Sendable {
    let sourceChangeID: String
    let envelope: CloudRecordEnvelope
    let serverRecordData: Data
    let receivedAt: Date
}

enum SyncConflictState: String, Codable, Sendable {
    case unresolved
    case resolved
}

enum CloudSyncConflictResolution: Equatable, Sendable {
    case keepLocal
    case useRemote
}

struct SyncConflictPayload: Codable, Equatable, Sendable {
    let localSnapshot: SyncRecordSnapshot
    let localChange: SyncChangeSet
    let remoteEnvelope: CloudRecordEnvelope
    let reasons: [SyncMergeConflictReason]
}

struct SyncRemoteApplyReport: Equatable, Sendable {
    let appliedCount: Int
    let conflictCount: Int
    let deferredCount: Int
    let failedCount: Int
}

struct CloudAssetMetadata: Equatable, Sendable {
    let contentHash: String
    let format: ImageAssetFormat
    let byteCount: Int
}

struct CloudRecordInventory: Equatable, Sendable {
    let recordCounts: [SyncRecordType: Int]
    let estimatedAssetBytes: Int64

    static let empty = CloudRecordInventory(
        recordCounts: [:],
        estimatedAssetBytes: 0
    )

    func count(for recordType: SyncRecordType) -> Int {
        recordCounts[recordType, default: 0]
    }
}

enum CloudSyncTransportFailure: Equatable, Sendable {
    case invalidRemoteData
    case remoteHardDeletion
    case zoneDeleted
    case statePersistence
    case localPersistence
    case cloudKit(code: Int)
}

enum CloudSyncTransportStatus: Equatable, Sendable {
    case stopped
    case idle
    case syncing
    case retrying
    case needsAccount
    case accountChanged
    case failed(CloudSyncTransportFailure)
}

enum SyncMergeOutcome: Equatable, Sendable {
    case merged(SyncChangeSet)
    case conflict(SyncMergeConflict)
}

enum SyncMergeEngine {
    static func merge(
        local: SyncChangeSet,
        remote: SyncChangeSet
    ) -> SyncMergeOutcome {
        guard local.recordType == remote.recordType,
              local.recordID == remote.recordID else {
            return conflict(local: local, remote: remote, reasons: [.differentRecords])
        }
        guard local.baseRevision == remote.baseRevision else {
            return conflict(
                local: local,
                remote: remote,
                reasons: [
                    .divergentBaseRevision(
                        local: local.baseRevision,
                        remote: remote.baseRevision
                    ),
                ]
            )
        }

        if local.operation == .delete || remote.operation == .delete {
            guard local.operation == .delete, remote.operation == .delete else {
                return conflict(
                    local: local,
                    remote: remote,
                    reasons: [.deletionVersusModification]
                )
            }
            return .merged(
                SyncChangeSet(
                    recordType: local.recordType,
                    recordID: local.recordID,
                    baseRevision: local.baseRevision,
                    targetRevision: max(local.targetRevision, remote.targetRevision),
                    operation: .delete,
                    fieldValues: [:],
                    relationshipChanges: []
                )
            )
        }

        var reasons: [SyncMergeConflictReason] = []
        let sharedFields = local.changedFields.intersection(remote.changedFields)
        let conflictingFields = Set(sharedFields.filter {
            local.fieldValues[$0] != remote.fieldValues[$0]
        })
        if !conflictingFields.isEmpty {
            reasons.append(.fields(conflictingFields))
        }

        for group in atomicFieldGroups(for: local.recordType) {
            let localFields = local.changedFields.intersection(group)
            let remoteFields = remote.changedFields.intersection(group)
            guard !localFields.isEmpty, !remoteFields.isEmpty else { continue }
            if localFields != remoteFields {
                reasons.append(.atomicFieldGroup(group))
            }
        }

        let relationshipConflicts = conflictingRelationships(
            local.relationshipChanges,
            remote.relationshipChanges
        )
        if !relationshipConflicts.isEmpty {
            reasons.append(.relationships(relationshipConflicts))
        }

        guard reasons.isEmpty else {
            return conflict(local: local, remote: remote, reasons: reasons)
        }

        var fieldValues = local.fieldValues
        fieldValues.merge(remote.fieldValues) { localValue, _ in localValue }
        let operation: SyncMutationOperation =
            local.operation == .create && remote.operation == .create
                ? .create
                : .update
        let highestRevision = max(
            local.targetRevision,
            remote.targetRevision
        )
        let (mergedRevision, overflow) = highestRevision.addingReportingOverflow(1)
        guard !overflow else {
            return conflict(
                local: local,
                remote: remote,
                reasons: [.revisionOverflow]
            )
        }
        return .merged(
            SyncChangeSet(
                recordType: local.recordType,
                recordID: local.recordID,
                baseRevision: local.baseRevision,
                targetRevision: mergedRevision,
                operation: operation,
                fieldValues: fieldValues,
                relationshipChanges: local.relationshipChanges
                    .union(remote.relationshipChanges)
            )
        )
    }

    private static func conflict(
        local: SyncChangeSet,
        remote: SyncChangeSet,
        reasons: [SyncMergeConflictReason]
    ) -> SyncMergeOutcome {
        .conflict(
            SyncMergeConflict(
                local: local,
                remote: remote,
                reasons: reasons
            )
        )
    }

    private static func atomicFieldGroups(
        for recordType: SyncRecordType
    ) -> [Set<String>] {
        switch recordType {
        case .subscription:
            [
                ["periodAmountMinor", "currencyCode", "currencyScale"],
                ["billingKindRaw", "cycleMonths"],
            ]
        case .subscriptionPeriod:
            [
                ["amountMinor", "currencyCode", "currencyScale"],
                ["billingKindRaw", "cycleMonths"],
            ]
        case .subscriptionPayment:
            [
                ["amountMinor", "currencyCode", "currencyScale"],
                ["periodStartDay", "periodEndDay"],
            ]
        case .serviceTemplate:
            [
                ["suggestedAmountMinor", "currencyCode", "currencyScale"],
                ["suggestedBillingKindRaw", "suggestedCycleMonths"],
            ]
        case .templateCategory,
             .builtinTemplateCategoryAssignment,
             .iconAsset:
            []
        }
    }

    private static func conflictingRelationships(
        _ local: Set<SyncRelationshipChange>,
        _ remote: Set<SyncRelationshipChange>
    ) -> Set<SyncRelationshipChange> {
        let remoteByIdentity = Dictionary(
            grouping: remote,
            by: RelationshipIdentity.init
        )
        return Set(local.filter { localChange in
            guard let remoteChanges = remoteByIdentity[RelationshipIdentity(localChange)] else {
                return false
            }
            return remoteChanges.contains {
                $0.operation != localChange.operation
            }
        })
    }

    private struct RelationshipIdentity: Hashable {
        let relationship: String
        let relatedRecordType: SyncRecordType
        let relatedRecordID: String

        init(_ change: SyncRelationshipChange) {
            relationship = change.relationship
            relatedRecordType = change.relatedRecordType
            relatedRecordID = change.relatedRecordID
        }
    }
}
