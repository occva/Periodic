import Foundation

struct DeviceIdentity: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let id: UUID
    let createdAt: Date

    init(
        formatVersion: Int = Self.currentFormatVersion,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.createdAt = createdAt
    }
}

struct DeviceIdentityRepository {
    let identityURL: URL
    private let fileManager: FileManager

    init(
        identityURL: URL,
        fileManager: FileManager = .default
    ) {
        self.identityURL = identityURL
        self.fileManager = fileManager
    }

    func loadOrCreate(now: Date = Date()) throws -> DeviceIdentity {
        if fileManager.fileExists(atPath: identityURL.path) {
            return try load()
        }
        let identity = DeviceIdentity(createdAt: now)
        try save(identity)
        return identity
    }

    func load() throws -> DeviceIdentity {
        do {
            let data = try Data(contentsOf: identityURL)
            let identity = try JSONDecoder().decode(DeviceIdentity.self, from: data)
            guard identity.formatVersion == DeviceIdentity.currentFormatVersion else {
                throw DeviceIdentityError.unsupportedFormat
            }
            return identity
        } catch let error as DeviceIdentityError {
            throw error
        } catch {
            throw DeviceIdentityError.invalidContents
        }
    }

    func save(_ identity: DeviceIdentity) throws {
        guard identity.formatVersion == DeviceIdentity.currentFormatVersion else {
            throw DeviceIdentityError.unsupportedFormat
        }
        do {
            try fileManager.createDirectory(
                at: identityURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(identity)
            try data.write(to: identityURL, options: .atomic)
        } catch {
            throw DeviceIdentityError.cannotSave
        }
    }
}

enum DeviceIdentityError: LocalizedError, Equatable {
    case invalidContents
    case unsupportedFormat
    case cannotSave

    var errorDescription: String? {
        switch self {
        case .invalidContents:
            "设备同步标识已损坏，已停止打开数据以避免产生重复设备。"
        case .unsupportedFormat:
            "设备同步标识来自不兼容的应用版本。"
        case .cannotSave:
            "无法保存设备同步标识。"
        }
    }
}
