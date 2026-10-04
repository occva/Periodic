import Foundation
import SwiftData

@Model
final class SyncConflictRecord {
    @Attribute(.unique) var sourceChangeID: String
    var conflictID: UUID
    var recordTypeRaw: String
    var recordID: String
    var payloadData: Data
    var remoteServerRecordData: Data
    var stateRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        sourceChangeID: String,
        recordType: SyncRecordType,
        recordID: String,
        payloadData: Data,
        remoteServerRecordData: Data,
        state: SyncConflictState = .unresolved,
        now: Date = Date()
    ) {
        self.sourceChangeID = sourceChangeID
        conflictID = UUID()
        recordTypeRaw = recordType.rawValue
        self.recordID = recordID
        self.payloadData = payloadData
        self.remoteServerRecordData = remoteServerRecordData
        stateRaw = state.rawValue
        createdAt = now
        updatedAt = now
    }
}
