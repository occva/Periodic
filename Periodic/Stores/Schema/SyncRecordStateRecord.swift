import Foundation
import SwiftData

@Model
final class SyncRecordStateRecord {
    @Attribute(.unique) var recordKey: String
    var recordTypeRaw: String
    var recordID: String
    var revision: Int64
    var modifiedAt: Date
    var modifiedByDeviceID: UUID
    var isDeleted: Bool
    var deletedAt: Date?
    var serverRecordData: Data?

    init(
        recordType: SyncRecordType,
        recordID: String,
        revision: Int64,
        modifiedAt: Date,
        modifiedByDeviceID: UUID,
        isDeleted: Bool,
        deletedAt: Date?,
        serverRecordData: Data? = nil
    ) {
        recordKey = Self.key(recordType: recordType, recordID: recordID)
        recordTypeRaw = recordType.rawValue
        self.recordID = recordID
        self.revision = revision
        self.modifiedAt = modifiedAt
        self.modifiedByDeviceID = modifiedByDeviceID
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.serverRecordData = serverRecordData
    }

    static func key(recordType: SyncRecordType, recordID: String) -> String {
        recordType.rawValue + ":" + recordID
    }
}
