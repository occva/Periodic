import Foundation
import SwiftData

@Model
final class DatasetMetadataRecord {
    static let activeKey = "active"

    @Attribute(.unique) var key: String
    var datasetID: UUID
    var storageKindRaw: String
    var schemaVersion: Int
    var cloudZoneName: String?
    var storeRevision: Int64
    var createdAt: Date
    var updatedAt: Date
    var lastSuccessfulSyncAt: Date?

    init(descriptor: DatasetDescriptor, now: Date = Date()) {
        key = Self.activeKey
        datasetID = descriptor.datasetID
        storageKindRaw = descriptor.storageKind.rawValue
        schemaVersion = descriptor.schemaVersion
        cloudZoneName = descriptor.cloudZoneName
        storeRevision = 0
        createdAt = descriptor.createdAt
        updatedAt = now
        lastSuccessfulSyncAt = descriptor.lastSuccessfulSyncAt
    }
}
