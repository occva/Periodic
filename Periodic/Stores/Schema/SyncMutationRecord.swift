import Foundation
import SwiftData

@Model
final class SyncMutationRecord {
    @Attribute(.unique) var mutationID: UUID
    var recordTypeRaw: String
    var recordID: String
    var baseRevision: Int64
    var targetRevision: Int64
    var changedFieldsData: Data
    var fieldValuesData: Data
    var relationshipChangesData: Data
    var operationRaw: String
    var stateRaw: String
    var deviceID: UUID
    var createdAt: Date
    var updatedAt: Date

    init(
        mutationID: UUID = UUID(),
        recordType: SyncRecordType,
        recordID: String,
        baseRevision: Int64,
        targetRevision: Int64,
        changedFieldsData: Data,
        fieldValuesData: Data,
        relationshipChangesData: Data,
        operation: SyncMutationOperation,
        state: SyncMutationState = .pending,
        deviceID: UUID,
        now: Date = Date()
    ) {
        self.mutationID = mutationID
        recordTypeRaw = recordType.rawValue
        self.recordID = recordID
        self.baseRevision = baseRevision
        self.targetRevision = targetRevision
        self.changedFieldsData = changedFieldsData
        self.fieldValuesData = fieldValuesData
        self.relationshipChangesData = relationshipChangesData
        operationRaw = operation.rawValue
        stateRaw = state.rawValue
        self.deviceID = deviceID
        createdAt = now
        updatedAt = now
    }
}
