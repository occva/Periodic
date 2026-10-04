import Foundation

enum DatasetStorageKind: String, Codable, Sendable {
    case local
    case iCloud
}

struct DatasetDescriptor: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    static let currentSchemaVersion = 9

    let formatVersion: Int
    let datasetID: UUID
    let storageKind: DatasetStorageKind
    let schemaVersion: Int
    let cloudZoneName: String?
    let createdAt: Date
    let lastSuccessfulSyncAt: Date?

    init(
        formatVersion: Int = currentFormatVersion,
        datasetID: UUID,
        storageKind: DatasetStorageKind,
        schemaVersion: Int = currentSchemaVersion,
        cloudZoneName: String? = nil,
        createdAt: Date = Date(),
        lastSuccessfulSyncAt: Date? = nil
    ) {
        self.formatVersion = formatVersion
        self.datasetID = datasetID
        self.storageKind = storageKind
        self.schemaVersion = schemaVersion
        self.cloudZoneName = cloudZoneName
        self.createdAt = createdAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    }

    static func local(datasetID: UUID = UUID(), createdAt: Date = Date()) -> Self {
        DatasetDescriptor(
            datasetID: datasetID,
            storageKind: .local,
            createdAt: createdAt
        )
    }

    func validated() throws -> Self {
        guard formatVersion == Self.currentFormatVersion else {
            throw DatasetDescriptorError.unsupportedFormat(formatVersion)
        }
        guard schemaVersion > 0 else {
            throw DatasetDescriptorError.invalidSchemaVersion
        }
        if storageKind == .iCloud {
            guard let cloudZoneName,
                  !cloudZoneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DatasetDescriptorError.missingCloudZone
            }
        }
        return self
    }
}

enum DatasetDescriptorError: LocalizedError, Equatable {
    case unsupportedFormat(Int)
    case invalidSchemaVersion
    case missingCloudZone
    case invalidContents

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "数据集描述来自较新的 Periodic 版本，请升级应用后重试。"
        case .invalidSchemaVersion:
            "数据集描述中的数据库版本无效。"
        case .missingCloudZone:
            "iCloud 数据集缺少同步区域标识。"
        case .invalidContents:
            "无法读取活动数据集描述，原有数据未被修改。"
        }
    }
}

struct DatasetDescriptorRepository: Sendable {
    let descriptorURL: URL

    func loadOrCreate(seedDatasetID: UUID, now: Date = Date()) throws -> DatasetDescriptor {
        if let existing = try load() {
            return existing
        }
        let descriptor = DatasetDescriptor.local(datasetID: seedDatasetID, createdAt: now)
        try save(descriptor)
        return descriptor
    }

    func load() throws -> DatasetDescriptor? {
        guard FileManager.default.fileExists(atPath: descriptorURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: descriptorURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DatasetDescriptor.self, from: data).validated()
        } catch let error as DatasetDescriptorError {
            throw error
        } catch {
            throw DatasetDescriptorError.invalidContents
        }
    }

    func save(_ descriptor: DatasetDescriptor) throws {
        let validated = try descriptor.validated()
        let directory = descriptorURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated)
        try data.write(to: descriptorURL, options: .atomic)
    }
}
