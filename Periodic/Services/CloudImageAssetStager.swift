import CryptoKit
import Foundation

actor CloudImageAssetStager {
    struct StagedImage: Hashable, Sendable {
        let leaseID: UUID
        let contentHash: String
        let format: ImageAssetFormat
        let byteCount: Int
        let fileURL: URL
    }

    enum StagingError: LocalizedError, Equatable {
        case invalidExpectedHash
        case hashMismatch
        case stagedFileMissing
        case invalidImage
        case unsupportedImageType
        case imageTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidExpectedHash:
                "云端图片校验值无效。"
            case .hashMismatch:
                "云端图片内容与校验值不一致，已停止导入。"
            case .stagedFileMissing:
                "临时图片已不存在，请重新同步。"
            case .invalidImage:
                "云端图片无法解码。"
            case .unsupportedImageType:
                "云端图片不是受支持的 PNG 或 JPEG 格式。"
            case .imageTooLarge:
                "云端图片超过允许大小。"
            }
        }
    }

    private let stagingRoot: URL
    private let fileManager: FileManager
    private var leaseCountByHash: [String: Int] = [:]
    private var hashByLeaseID: [UUID: String] = [:]

    init(
        stagingRoot: URL,
        fileManager: FileManager = .default
    ) {
        self.stagingRoot = stagingRoot
        self.fileManager = fileManager
    }

    func stage(
        fileURL: URL,
        expectedContentHash: String
    ) throws -> StagedImage {
        try validateHash(expectedContentHash)
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = resourceValues.fileSize,
           fileSize > ImageAssetValidator.maximumImageSize {
            throw StagingError.imageTooLarge
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(
            upToCount: ImageAssetValidator.maximumImageSize + 1
        ) ?? Data()
        return try stage(
            data: data,
            expectedContentHash: expectedContentHash
        )
    }

    func stage(
        data: Data,
        expectedContentHash: String
    ) throws -> StagedImage {
        try validateHash(expectedContentHash)
        guard data.count <= ImageAssetValidator.maximumImageSize else {
            throw StagingError.imageTooLarge
        }
        let format: ImageAssetFormat
        do {
            format = try ImageAssetValidator.validate(data)
        } catch let error as ImageAssetValidationError {
            switch error {
            case .invalidImage:
                throw StagingError.invalidImage
            case .unsupportedImageType:
                throw StagingError.unsupportedImageType
            case .imageTooLarge:
                throw StagingError.imageTooLarge
            }
        }
        let actualHash = Self.contentHash(of: data)
        guard actualHash == expectedContentHash.lowercased() else {
            throw StagingError.hashMismatch
        }

        try fileManager.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true
        )
        let destination = stagingRoot
            .appending(path: actualHash)
            .appendingPathExtension(format.filenameExtension)
        if !fileManager.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: .atomic)
        }
        let leaseID = UUID()
        leaseCountByHash[actualHash, default: 0] += 1
        hashByLeaseID[leaseID] = actualHash
        return StagedImage(
            leaseID: leaseID,
            contentHash: actualHash,
            format: format,
            byteCount: data.count,
            fileURL: destination
        )
    }

    func data(for stagedImage: StagedImage) throws -> Data {
        guard fileManager.fileExists(atPath: stagedImage.fileURL.path) else {
            throw StagingError.stagedFileMissing
        }
        let data = try Data(contentsOf: stagedImage.fileURL)
        guard Self.contentHash(of: data) == stagedImage.contentHash else {
            throw StagingError.hashMismatch
        }
        _ = try ImageAssetValidator.validate(data)
        return data
    }

    func acquireExisting(
        metadata: CloudAssetMetadata
    ) throws -> StagedImage {
        let source = stagingRoot
            .appending(path: metadata.contentHash)
            .appendingPathExtension(metadata.format.filenameExtension)
        guard fileManager.fileExists(atPath: source.path) else {
            throw StagingError.stagedFileMissing
        }
        let staged = try stage(
            fileURL: source,
            expectedContentHash: metadata.contentHash
        )
        guard staged.format == metadata.format,
              staged.byteCount == metadata.byteCount else {
            release([staged])
            throw StagingError.hashMismatch
        }
        return staged
    }

    func release(_ stagedImages: [StagedImage]) {
        for stagedImage in stagedImages {
            guard hashByLeaseID.removeValue(forKey: stagedImage.leaseID)
                    == stagedImage.contentHash,
                  let count = leaseCountByHash[stagedImage.contentHash] else {
                continue
            }
            if count > 1 {
                leaseCountByHash[stagedImage.contentHash] = count - 1
                continue
            }
            leaseCountByHash.removeValue(forKey: stagedImage.contentHash)
            do {
                if fileManager.fileExists(atPath: stagedImage.fileURL.path) {
                    try fileManager.removeItem(at: stagedImage.fileURL)
                }
            } catch {
                AppLog.persistence.error("Failed to remove a staged cloud image")
            }
        }
    }

    private func validateHash(_ hash: String) throws {
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else {
            throw StagingError.invalidExpectedHash
        }
    }

    static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
