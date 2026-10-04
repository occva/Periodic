import CloudKit
import Foundation

enum CloudRecordCodec {
    struct InventoryEntry: Equatable, Sendable {
        let recordType: SyncRecordType
        let isDeleted: Bool
        let assetByteCount: Int
    }

    enum CodecError: LocalizedError, Equatable {
        case invalidRecordType
        case invalidRecordID
        case invalidRevision
        case invalidModifiedAt
        case invalidDeviceID
        case invalidDeletedFlag
        case invalidPayload
        case missingAsset
        case mismatchedRecordIdentity
        case invalidSystemFields

        var errorDescription: String? {
            switch self {
            case .invalidRecordType:
                "iCloud 记录类型无法识别。"
            case .invalidRecordID:
                "iCloud 记录标识无效。"
            case .invalidRevision:
                "iCloud 记录版本无效。"
            case .invalidModifiedAt:
                "iCloud 记录修改时间无效。"
            case .invalidDeviceID:
                "iCloud 记录设备标识无效。"
            case .invalidDeletedFlag:
                "iCloud 记录删除状态无效。"
            case .invalidPayload:
                "iCloud 记录正文无法读取。"
            case .missingAsset:
                "iCloud 图片记录缺少文件。"
            case .mismatchedRecordIdentity:
                "iCloud 记录正文与系统标识不一致。"
            case .invalidSystemFields:
                "iCloud 记录系统元数据无法读取。"
            }
        }
    }

    static func makeRecord(
        snapshot: SyncRecordSnapshot,
        baseRevision: Int64,
        changedFields: Set<String>,
        relationshipChanges: Set<SyncRelationshipChange>,
        zoneID: CKRecordZone.ID,
        assetFileURL: URL? = nil,
        assetMetadata: CloudAssetMetadata? = nil
    ) throws -> CKRecord {
        let expectedRecordID = cloudRecordID(
            recordType: snapshot.recordType,
            recordID: snapshot.recordID,
            zoneID: zoneID
        )
        let record: CKRecord
        if let systemFields = snapshot.serverRecordData {
            record = try decodeSystemFields(systemFields)
            guard record.recordID == expectedRecordID else {
                throw CodecError.mismatchedRecordIdentity
            }
        } else {
            record = CKRecord(
                recordType: cloudRecordType(snapshot.recordType),
                recordID: expectedRecordID
            )
        }

        record[Field.recordType] = snapshot.recordType.rawValue as CKRecordValue
        record[Field.recordID] = snapshot.recordID as CKRecordValue
        record[Field.revision] = NSNumber(value: snapshot.revision)
        record[Field.modifiedAt] = snapshot.modifiedAt as CKRecordValue
        record[Field.modifiedByDeviceID] =
            snapshot.modifiedByDeviceID.uuidString as CKRecordValue
        record[Field.isDeleted] = NSNumber(value: snapshot.isDeleted)
        if let deletedAt = snapshot.deletedAt {
            record[Field.deletedAt] = deletedAt as CKRecordValue
        } else {
            record[Field.deletedAt] = nil
        }
        record[Field.payload] = try JSONEncoder()
            .encode(snapshot.fieldValues) as CKRecordValue
        record[Field.baseRevision] = NSNumber(value: baseRevision)
        record[Field.changedFields] = try JSONEncoder()
            .encode(changedFields.sorted()) as CKRecordValue
        record[Field.relationshipChanges] = try JSONEncoder()
            .encode(
                relationshipChanges.sorted(by: relationshipSort)
            ) as CKRecordValue
        if snapshot.recordType == .iconAsset, !snapshot.isDeleted {
            guard let assetFileURL, let assetMetadata else {
                throw CodecError.missingAsset
            }
            let payload = try SyncRecordPayloadDecoder.iconAsset(
                recordID: snapshot.recordID,
                fieldValues: snapshot.fieldValues
            )
            guard payload.metadata == assetMetadata else {
                throw CodecError.invalidPayload
            }
            record[Field.asset] = CKAsset(fileURL: assetFileURL)
            record[Field.assetContentHash] =
                assetMetadata.contentHash as CKRecordValue
            record[Field.assetFormat] =
                assetMetadata.format.rawValue as CKRecordValue
            record[Field.assetByteCount] = NSNumber(
                value: assetMetadata.byteCount
            )
        } else {
            record[Field.asset] = nil
            record[Field.assetContentHash] = nil
            record[Field.assetFormat] = nil
            record[Field.assetByteCount] = nil
        }
        return record
    }

    static func makeRecord(
        upload: SyncUploadRecord,
        zoneID: CKRecordZone.ID,
        assetFileURL: URL? = nil,
        assetMetadata: CloudAssetMetadata? = nil
    ) throws -> CKRecord {
        try makeRecord(
            snapshot: upload.snapshot,
            baseRevision: upload.baseRevision,
            changedFields: upload.changedFields,
            relationshipChanges: upload.relationshipChanges,
            zoneID: zoneID,
            assetFileURL: assetFileURL,
            assetMetadata: assetMetadata
        )
    }

    static func decode(_ record: CKRecord) throws -> CloudRecordEnvelope {
        guard let recordTypeRaw = record[Field.recordType] as? String,
              let recordType = SyncRecordType(rawValue: recordTypeRaw) else {
            throw CodecError.invalidRecordType
        }
        guard cloudRecordType(recordType) == record.recordType else {
            throw CodecError.mismatchedRecordIdentity
        }
        guard let recordID = record[Field.recordID] as? String,
              !recordID.isEmpty else {
            throw CodecError.invalidRecordID
        }
        let expectedName = cloudRecordName(
            recordType: recordType,
            recordID: recordID
        )
        guard record.recordID.recordName == expectedName else {
            throw CodecError.mismatchedRecordIdentity
        }
        guard let revisionNumber = record[Field.revision] as? NSNumber,
              revisionNumber.int64Value > 0 else {
            throw CodecError.invalidRevision
        }
        guard let modifiedAt = record[Field.modifiedAt] as? Date else {
            throw CodecError.invalidModifiedAt
        }
        guard let deviceIDRaw = record[Field.modifiedByDeviceID] as? String,
              let deviceID = UUID(uuidString: deviceIDRaw) else {
            throw CodecError.invalidDeviceID
        }
        guard let deletedNumber = record[Field.isDeleted] as? NSNumber else {
            throw CodecError.invalidDeletedFlag
        }
        guard let payloadData = record[Field.payload] as? Data,
              var fieldValues = try? JSONDecoder().decode(
                [String: SyncValue].self,
                from: payloadData
              ) else {
            throw CodecError.invalidPayload
        }
        guard let baseRevisionNumber = record[Field.baseRevision] as? NSNumber,
              baseRevisionNumber.int64Value >= 0 else {
            throw CodecError.invalidRevision
        }
        guard let changedFieldsData = record[Field.changedFields] as? Data,
              let decodedChangedFields = try? JSONDecoder().decode(
                [String].self,
                from: changedFieldsData
              ) else {
            throw CodecError.invalidPayload
        }
        var changedFields = Set(decodedChangedFields)
        guard let relationshipsData = record[Field.relationshipChanges] as? Data,
              let relationshipChanges = try? JSONDecoder().decode(
                [SyncRelationshipChange].self,
                from: relationshipsData
              ) else {
            throw CodecError.invalidPayload
        }
        let isDeleted = deletedNumber.boolValue
        let deletedAt = record[Field.deletedAt] as? Date
        guard !isDeleted || deletedAt != nil else {
            throw CodecError.invalidDeletedFlag
        }
        guard !isDeleted || fieldValues.isEmpty else {
            throw CodecError.invalidPayload
        }
        if recordType == .iconAsset, !isDeleted {
            let metadata = try assetMetadata(for: record)
            let normalizedPayload = SyncRecordPayload.iconAsset(
                reference: recordID,
                metadata: metadata
            )
            if Set(fieldValues.keys) == ["reference"] {
                fieldValues = normalizedPayload
                changedFields.formUnion(normalizedPayload.keys)
            } else {
                let payload = try SyncRecordPayloadDecoder.iconAsset(
                    recordID: recordID,
                    fieldValues: fieldValues
                )
                guard payload.metadata == metadata else {
                    throw CodecError.invalidPayload
                }
            }
            if baseRevisionNumber.int64Value == 0 {
                changedFields.formUnion(fieldValues.keys)
            }
        }
        return CloudRecordEnvelope(
            recordType: recordType,
            recordID: recordID,
            revision: revisionNumber.int64Value,
            modifiedAt: modifiedAt,
            modifiedByDeviceID: deviceID,
            isDeleted: isDeleted,
            deletedAt: deletedAt,
            fieldValues: fieldValues,
            baseRevision: baseRevisionNumber.int64Value,
            changedFields: changedFields,
            relationshipChanges: Set(relationshipChanges)
        )
    }

    static func systemFieldsData(for record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func validateSystemFieldsData(
        _ data: Data,
        envelope: CloudRecordEnvelope
    ) throws {
        let record = try decodeSystemFields(data)
        guard record.recordType == cloudRecordType(envelope.recordType),
              record.recordID.recordName == cloudRecordName(
                recordType: envelope.recordType,
                recordID: envelope.recordID
              ) else {
            throw CodecError.mismatchedRecordIdentity
        }
    }

    static func assetFileURL(for record: CKRecord) throws -> URL {
        guard let asset = record[Field.asset] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CodecError.missingAsset
        }
        return fileURL
    }

    static func assetMetadata(
        for record: CKRecord
    ) throws -> CloudAssetMetadata {
        guard record[Field.asset] is CKAsset,
              let contentHash = record[Field.assetContentHash] as? String,
              contentHash.count == 64,
              contentHash.allSatisfy(\.isHexDigit),
              let formatRaw = record[Field.assetFormat] as? String,
              let format = ImageAssetFormat(rawValue: formatRaw),
              let byteCount = record[Field.assetByteCount] as? NSNumber,
              byteCount.intValue > 0,
              byteCount.intValue <= ImageAssetValidator.maximumImageSize else {
            throw CodecError.missingAsset
        }
        return CloudAssetMetadata(
            contentHash: contentHash.lowercased(),
            format: format,
            byteCount: byteCount.intValue
        )
    }

    static var inventoryDesiredKeys: [CKRecord.FieldKey] {
        [
            Field.recordType,
            Field.recordID,
            Field.isDeleted,
            Field.assetByteCount,
        ]
    }

    static func decodeInventoryEntry(
        _ record: CKRecord
    ) throws -> InventoryEntry {
        guard let recordTypeRaw = record[Field.recordType] as? String,
              let recordType = SyncRecordType(rawValue: recordTypeRaw) else {
            throw CodecError.invalidRecordType
        }
        guard cloudRecordType(recordType) == record.recordType else {
            throw CodecError.mismatchedRecordIdentity
        }
        guard let recordID = record[Field.recordID] as? String,
              !recordID.isEmpty else {
            throw CodecError.invalidRecordID
        }
        guard record.recordID.recordName == cloudRecordName(
            recordType: recordType,
            recordID: recordID
        ) else {
            throw CodecError.mismatchedRecordIdentity
        }
        guard let deletedNumber = record[Field.isDeleted] as? NSNumber else {
            throw CodecError.invalidDeletedFlag
        }
        let isDeleted = deletedNumber.boolValue
        let assetByteCount: Int
        if recordType == .iconAsset, !isDeleted {
            guard let byteCount = record[Field.assetByteCount] as? NSNumber,
                  byteCount.intValue > 0,
                  byteCount.intValue
                    <= ImageAssetValidator.maximumImageSize else {
                throw CodecError.missingAsset
            }
            assetByteCount = byteCount.intValue
        } else {
            assetByteCount = 0
        }
        return InventoryEntry(
            recordType: recordType,
            isDeleted: isDeleted,
            assetByteCount: assetByteCount
        )
    }

    static func cloudRecordID(
        recordType: SyncRecordType,
        recordID: String,
        zoneID: CKRecordZone.ID
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: cloudRecordName(
                recordType: recordType,
                recordID: recordID
            ),
            zoneID: zoneID
        )
    }

    private static func decodeSystemFields(_ data: Data) throws -> CKRecord {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            defer { unarchiver.finishDecoding() }
            guard let record = CKRecord(coder: unarchiver) else {
                throw CodecError.invalidSystemFields
            }
            return record
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.invalidSystemFields
        }
    }

    private static func cloudRecordName(
        recordType: SyncRecordType,
        recordID: String
    ) -> String {
        recordType.rawValue + "." + recordID
    }

    static func cloudRecordType(_ recordType: SyncRecordType) -> String {
        switch recordType {
        case .subscription:
            "PeriodicSubscription"
        case .subscriptionPeriod:
            "PeriodicSubscriptionPeriod"
        case .subscriptionPayment:
            "PeriodicSubscriptionPayment"
        case .serviceTemplate:
            "PeriodicServiceTemplate"
        case .templateCategory:
            "PeriodicTemplateCategory"
        case .builtinTemplateCategoryAssignment:
            "PeriodicBuiltinCategoryAssignment"
        case .iconAsset:
            "PeriodicIconAsset"
        }
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

    private enum Field {
        static let recordType = "periodicRecordType"
        static let recordID = "periodicRecordID"
        static let revision = "revision"
        static let modifiedAt = "modifiedAt"
        static let modifiedByDeviceID = "modifiedByDeviceID"
        static let isDeleted = "isDeleted"
        static let deletedAt = "deletedAt"
        static let payload = "payload"
        static let baseRevision = "baseRevision"
        static let changedFields = "changedFields"
        static let relationshipChanges = "relationshipChanges"
        static let asset = "asset"
        static let assetContentHash = "assetContentHash"
        static let assetFormat = "assetFormat"
        static let assetByteCount = "assetByteCount"
    }
}
