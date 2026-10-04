import CloudKit
import Foundation
import Testing
@testable import Periodic

struct CloudRecordCodecTests {
    @Test func recordRoundTripsBusinessPayloadAndIdentity() throws {
        let zoneID = CKRecordZone.ID(zoneName: "Periodic")
        let deviceID = UUID()
        let snapshot = SyncRecordSnapshot(
            recordType: .subscription,
            recordID: UUID().uuidString,
            revision: 4,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedByDeviceID: deviceID,
            isDeleted: false,
            deletedAt: nil,
            fieldValues: [
                "name": .string("Periodic"),
                "periodAmountMinor": .integer(8_800),
            ],
            serverRecordData: nil
        )

        let record = try CloudRecordCodec.makeRecord(
            snapshot: snapshot,
            baseRevision: 3,
            changedFields: ["name", "periodAmountMinor"],
            relationshipChanges: [],
            zoneID: zoneID
        )
        let decoded = try CloudRecordCodec.decode(record)

        #expect(decoded.recordType == snapshot.recordType)
        #expect(decoded.recordID == snapshot.recordID)
        #expect(decoded.revision == snapshot.revision)
        #expect(decoded.modifiedAt == snapshot.modifiedAt)
        #expect(decoded.modifiedByDeviceID == deviceID)
        #expect(decoded.fieldValues == snapshot.fieldValues)
        #expect(decoded.baseRevision == 3)
        #expect(decoded.changedFields == ["name", "periodAmountMinor"])
        #expect(record.recordID.zoneID == zoneID)
    }

    @Test func tombstoneRoundTripsWithoutBusinessPayload() throws {
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let snapshot = SyncRecordSnapshot(
            recordType: .subscriptionPeriod,
            recordID: UUID().uuidString,
            revision: 3,
            modifiedAt: deletedAt,
            modifiedByDeviceID: UUID(),
            isDeleted: true,
            deletedAt: deletedAt,
            fieldValues: [:],
            serverRecordData: nil
        )

        let record = try CloudRecordCodec.makeRecord(
            snapshot: snapshot,
            baseRevision: 2,
            changedFields: [],
            relationshipChanges: [],
            zoneID: CKRecordZone.ID(zoneName: "Periodic")
        )
        let decoded = try CloudRecordCodec.decode(record)

        #expect(decoded.isDeleted)
        #expect(decoded.deletedAt == deletedAt)
        #expect(decoded.fieldValues.isEmpty)
    }

    @Test func systemFieldsReopenTheSameCloudRecordIdentity() throws {
        let zoneID = CKRecordZone.ID(zoneName: "Periodic")
        let original = SyncRecordSnapshot(
            recordType: .templateCategory,
            recordID: UUID().uuidString,
            revision: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedByDeviceID: UUID(),
            isDeleted: false,
            deletedAt: nil,
            fieldValues: ["name": .string("Work")],
            serverRecordData: nil
        )
        let firstRecord = try CloudRecordCodec.makeRecord(
            snapshot: original,
            baseRevision: 0,
            changedFields: ["name"],
            relationshipChanges: [],
            zoneID: zoneID
        )
        let updated = SyncRecordSnapshot(
            recordType: original.recordType,
            recordID: original.recordID,
            revision: 2,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
            modifiedByDeviceID: original.modifiedByDeviceID,
            isDeleted: false,
            deletedAt: nil,
            fieldValues: ["name": .string("Tools")],
            serverRecordData: CloudRecordCodec.systemFieldsData(for: firstRecord)
        )

        let reopened = try CloudRecordCodec.makeRecord(
            snapshot: updated,
            baseRevision: 1,
            changedFields: ["name"],
            relationshipChanges: [],
            zoneID: zoneID
        )

        #expect(reopened.recordID == firstRecord.recordID)
        #expect(try CloudRecordCodec.decode(reopened).revision == 2)
    }

    @Test func assetMetadataParticipatesInTheBusinessPayload() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        let hash = CloudImageAssetStager.contentHash(of: data)
        let reference = AppleIconCache.localReferencePrefix + hash
        let metadata = CloudAssetMetadata(
            contentHash: hash,
            format: .png,
            byteCount: data.count
        )
        let fileURL = root.appending(path: "asset.png")
        try data.write(to: fileURL)
        let snapshot = SyncRecordSnapshot(
            recordType: .iconAsset,
            recordID: reference,
            revision: 1,
            modifiedAt: .now,
            modifiedByDeviceID: UUID(),
            isDeleted: false,
            deletedAt: nil,
            fieldValues: SyncRecordPayload.iconAsset(
                reference: reference,
                metadata: metadata
            ),
            serverRecordData: nil
        )

        let record = try CloudRecordCodec.makeRecord(
            snapshot: snapshot,
            baseRevision: 0,
            changedFields: Set(snapshot.fieldValues.keys),
            relationshipChanges: [],
            zoneID: CKRecordZone.ID(zoneName: "Periodic"),
            assetFileURL: fileURL,
            assetMetadata: metadata
        )
        let decoded = try CloudRecordCodec.decode(record)

        #expect(decoded.fieldValues == snapshot.fieldValues)
        #expect(decoded.changedFields == Set(snapshot.fieldValues.keys))
    }

    @Test func rejectsAssetWhoseCloudMetadataDiffersFromPayload() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        let hash = CloudImageAssetStager.contentHash(of: data)
        let reference = AppleIconCache.localReferencePrefix + hash
        let metadata = CloudAssetMetadata(
            contentHash: hash,
            format: .png,
            byteCount: data.count
        )
        let fileURL = root.appending(path: "asset.png")
        try data.write(to: fileURL)
        let snapshot = SyncRecordSnapshot(
            recordType: .iconAsset,
            recordID: reference,
            revision: 1,
            modifiedAt: .now,
            modifiedByDeviceID: UUID(),
            isDeleted: false,
            deletedAt: nil,
            fieldValues: SyncRecordPayload.iconAsset(
                reference: reference,
                metadata: metadata
            ),
            serverRecordData: nil
        )

        #expect(throws: CloudRecordCodec.CodecError.invalidPayload) {
            try CloudRecordCodec.makeRecord(
                snapshot: snapshot,
                baseRevision: 0,
                changedFields: Set(snapshot.fieldValues.keys),
                relationshipChanges: [],
                zoneID: CKRecordZone.ID(zoneName: "Periodic"),
                assetFileURL: fileURL,
                assetMetadata: CloudAssetMetadata(
                    contentHash: String(repeating: "a", count: 64),
                    format: .png,
                    byteCount: data.count
                )
            )
        }
    }

    @Test func inventoryEntryDoesNotRequireAssetContents() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        let hash = CloudImageAssetStager.contentHash(of: data)
        let reference = AppleIconCache.localReferencePrefix + hash
        let metadata = CloudAssetMetadata(
            contentHash: hash,
            format: .png,
            byteCount: data.count
        )
        let fileURL = root.appending(path: "asset.png")
        try data.write(to: fileURL)
        let snapshot = SyncRecordSnapshot(
            recordType: .iconAsset,
            recordID: reference,
            revision: 1,
            modifiedAt: .now,
            modifiedByDeviceID: UUID(),
            isDeleted: false,
            deletedAt: nil,
            fieldValues: SyncRecordPayload.iconAsset(
                reference: reference,
                metadata: metadata
            ),
            serverRecordData: nil
        )
        let record = try CloudRecordCodec.makeRecord(
            snapshot: snapshot,
            baseRevision: 0,
            changedFields: Set(snapshot.fieldValues.keys),
            relationshipChanges: [],
            zoneID: CKRecordZone.ID(zoneName: "Periodic"),
            assetFileURL: fileURL,
            assetMetadata: metadata
        )
        record["asset"] = nil

        let entry = try CloudRecordCodec.decodeInventoryEntry(record)

        #expect(entry.recordType == .iconAsset)
        #expect(!entry.isDeleted)
        #expect(entry.assetByteCount == data.count)
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
