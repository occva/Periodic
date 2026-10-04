import Foundation
import SwiftData

struct DatasetVersion: Equatable, Sendable {
    let datasetID: UUID
    let storeRevision: Int64
}

enum DatasetMetadata {
    static func prepare(
        in context: ModelContext,
        descriptor: DatasetDescriptor
    ) throws -> DatasetMetadataRecord {
        let record = try fetchOrCreate(in: context, descriptor: descriptor)
        var changed = false
        if record.schemaVersion != descriptor.schemaVersion {
            record.schemaVersion = descriptor.schemaVersion
            changed = true
        }
        if record.storageKindRaw != descriptor.storageKind.rawValue {
            record.storageKindRaw = descriptor.storageKind.rawValue
            changed = true
        }
        if record.cloudZoneName != descriptor.cloudZoneName {
            record.cloudZoneName = descriptor.cloudZoneName
            changed = true
        }
        if record.lastSuccessfulSyncAt != descriptor.lastSuccessfulSyncAt {
            record.lastSuccessfulSyncAt = descriptor.lastSuccessfulSyncAt
            changed = true
        }
        if changed || context.hasChanges {
            record.updatedAt = .now
            try context.save()
        }
        return record
    }

    static func currentVersion(
        in context: ModelContext,
        descriptor: DatasetDescriptor? = nil
    ) throws -> DatasetVersion {
        let record = try fetchOrCreate(in: context, descriptor: descriptor)
        return DatasetVersion(
            datasetID: record.datasetID,
            storeRevision: record.storeRevision
        )
    }

    @discardableResult
    static func advanceRevision(
        in context: ModelContext,
        descriptor: DatasetDescriptor? = nil,
        now: Date = Date()
    ) throws -> DatasetVersion {
        let record = try fetchOrCreate(in: context, descriptor: descriptor)
        let (nextRevision, overflow) = record.storeRevision.addingReportingOverflow(1)
        guard !overflow else {
            throw DatasetMetadataError.revisionOverflow
        }
        record.storeRevision = nextRevision
        record.updatedAt = now
        return DatasetVersion(
            datasetID: record.datasetID,
            storeRevision: nextRevision
        )
    }

    private static func fetchOrCreate(
        in context: ModelContext,
        descriptor: DatasetDescriptor?
    ) throws -> DatasetMetadataRecord {
        let records = try context.fetch(FetchDescriptor<DatasetMetadataRecord>())
        guard records.count <= 1 else {
            throw DatasetMetadataError.duplicateMetadata
        }
        if let record = records.first {
            if let descriptor, record.datasetID != descriptor.datasetID {
                throw DatasetMetadataError.datasetMismatch
            }
            return record
        }

        let resolvedDescriptor = descriptor ?? .local()
        let record = DatasetMetadataRecord(descriptor: resolvedDescriptor)
        context.insert(record)
        return record
    }
}

enum DatasetMetadataError: LocalizedError, Equatable {
    case duplicateMetadata
    case datasetMismatch
    case revisionOverflow

    var errorDescription: String? {
        switch self {
        case .duplicateMetadata:
            "数据库包含重复的数据集元数据，已停止写入以保护现有数据。"
        case .datasetMismatch:
            "活动数据集与数据库不匹配，已停止写入以避免覆盖其他数据集。"
        case .revisionOverflow:
            "数据库版本计数已达到上限，无法继续写入。"
        }
    }
}
