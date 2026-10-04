import Foundation
import SwiftData

@Model
final class SyncRemoteChangeRecord {
    @Attribute(.unique) var sourceChangeID: String
    var recordTypeRaw: String
    var recordID: String
    var envelopeData: Data
    var serverRecordData: Data
    var stateRaw: String
    var failureCode: String?
    var receivedAt: Date
    var updatedAt: Date

    init(
        sourceChangeID: String,
        envelope: CloudRecordEnvelope,
        envelopeData: Data,
        serverRecordData: Data,
        state: SyncRemoteChangeState = .pending,
        receivedAt: Date
    ) {
        self.sourceChangeID = sourceChangeID
        recordTypeRaw = envelope.recordType.rawValue
        recordID = envelope.recordID
        self.envelopeData = envelopeData
        self.serverRecordData = serverRecordData
        stateRaw = state.rawValue
        failureCode = nil
        self.receivedAt = receivedAt
        updatedAt = receivedAt
    }
}
