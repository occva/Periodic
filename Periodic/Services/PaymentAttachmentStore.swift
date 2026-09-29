import CryptoKit
import Foundation

actor PaymentAttachmentStore {
    private static let storedImageExtensions = ["png", "jpg", "image"]

    struct ImportedImageWrite: Sendable {
        let reference: String
        fileprivate let leaseID: UUID
    }

    enum StoreError: LocalizedError {
        case invalidReference
        case invalidImage
        case unsupportedImageType
        case imageTooLarge
        case storedImageMissing

        var errorDescription: String? {
            switch self {
            case .invalidReference: AppLocalization.string("消费截图引用无效。")
            case .invalidImage: AppLocalization.string("所选文件不是可解码的图片。")
            case .unsupportedImageType: AppLocalization.string("请选择 PNG 或 JPEG 图片。")
            case .imageTooLarge: AppLocalization.string("消费截图文件过大，无法保存。")
            case .storedImageMissing: AppLocalization.string("已保存的消费截图不存在。")
            }
        }
    }

    private let fileManager: FileManager
    private let storageRoot: URL?
    private var activeLeaseIDsByReference: [String: Set<UUID>] = [:]

    init(
        fileManager: FileManager = .default,
        storageRoot: URL? = nil
    ) {
        self.fileManager = fileManager
        self.storageRoot = storageRoot
    }

    func persistLocalImage(from url: URL) throws -> ImportedImageWrite {
        let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = resourceValues.fileSize,
           fileSize > ImageAssetValidator.maximumImageSize {
            throw StoreError.imageTooLarge
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(
            upToCount: ImageAssetValidator.maximumImageSize + 1
        ) ?? Data()
        return try persistImage(data)
    }

    func persistImportedImage(_ data: Data) throws -> ImportedImageWrite {
        try persistImage(data)
    }

    func data(for reference: String) throws -> Data {
        let key = try cacheKey(from: reference)
        guard let source = try storedImageURL(key: key)
            ?? recoverFromLocalIconCache(key: key) else {
            throw StoreError.storedImageMissing
        }
        return try Data(contentsOf: source)
    }

    func previewURL(for reference: String) throws -> URL {
        let key = try cacheKey(from: reference)
        guard let source = try storedImageURL(key: key)
            ?? recoverFromLocalIconCache(key: key) else {
            throw StoreError.storedImageMissing
        }
        let storedURL: URL
        if source.pathExtension == "image" {
            let data = try Data(contentsOf: source)
            let format = try validate(data)
            let destination = try storedImageDirectory()
                .appending(path: key)
                .appendingPathExtension(format.filenameExtension)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: source)
            } else {
                try fileManager.moveItem(at: source, to: destination)
            }
            storedURL = destination
        } else {
            storedURL = source
        }
        return try makeQuickLookPreviewURL(source: storedURL, key: key)
    }

    func previewURLs(for references: [String]) throws -> [URL] {
        try references.map(previewURL(for:))
    }

    func discardImportedImages(
        _ writes: [ImportedImageWrite],
        keeping references: Set<String> = []
    ) {
        let releasedReferences = releaseLeases(for: writes)
        removeReleasedImages(references: releasedReferences, keeping: references)
    }

    /// Ends draft ownership after its references have committed to the database.
    /// Committed files are never deleted here because database visibility and
    /// view dismissal can occur in different tasks.
    func releaseImportedImages(_ writes: [ImportedImageWrite]) {
        _ = releaseLeases(for: writes)
    }

    private func releaseLeases(for writes: [ImportedImageWrite]) -> Set<String> {
        for write in writes {
            activeLeaseIDsByReference[write.reference]?.remove(write.leaseID)
            if activeLeaseIDsByReference[write.reference]?.isEmpty == true {
                activeLeaseIDsByReference.removeValue(forKey: write.reference)
            }
        }
        return Set(writes.map(\.reference))
    }

    private func removeReleasedImages(
        references releasedReferences: Set<String>,
        keeping references: Set<String>
    ) {
        for reference in releasedReferences
        where !references.contains(reference) && activeLeaseIDsByReference[reference] == nil {
            do {
                let key = try cacheKey(from: reference)
                try removeStoredImage(key: key)
            } catch {
                AppLog.persistence.error(
                    "Failed to discard an unreferenced imported payment attachment"
                )
            }
        }
    }

    func removeStoredImages(references: Set<String>) -> Set<String> {
        var failedReferences = Set<String>()
        for reference in references {
            guard activeLeaseIDsByReference[reference] == nil else {
                failedReferences.insert(reference)
                continue
            }
            do {
                let key = try cacheKey(from: reference)
                try removeStoredImage(key: key)
            } catch {
                if (error as NSError).code != NSFileNoSuchFileError {
                    failedReferences.insert(reference)
                    AppLog.persistence.error("Failed to remove an unreferenced payment attachment")
                }
            }
        }
        return failedReferences
    }

    func removeUnreferencedImages(
        keeping references: Set<String>,
        modifiedBefore cutoff: Date
    ) -> Set<String> {
        let directory: URL
        do {
            directory = try storedImageDirectory()
        } catch {
            AppLog.persistence.error("Failed to inspect stored payment attachments")
            return []
        }
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
        } catch {
            AppLog.persistence.error("Failed to list stored payment attachments")
            return []
        }
        let orphanedReferences = Set(urls.compactMap { url -> String? in
            guard Self.storedImageExtensions.contains(url.pathExtension) else { return nil }
            guard let modifiedAt = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate,
                  modifiedAt < cutoff else { return nil }
            let key = url.deletingPathExtension().lastPathComponent
            guard key.count == 64, key.allSatisfy(\.isHexDigit) else { return nil }
            return PaymentAttachmentReference.make(contentHash: key)
        }).subtracting(references).subtracting(activeLeaseIDsByReference.keys)
        return removeStoredImages(references: orphanedReferences)
    }

    private func persistImage(_ data: Data) throws -> ImportedImageWrite {
        let format = try validate(data)
        let key = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let existingURL = try storedImageURL(key: key)
        let destination = try storedImageDirectory()
            .appending(path: key)
            .appendingPathExtension(format.filenameExtension)
        let didCreateFile = existingURL == nil
        if didCreateFile {
            try data.write(to: destination, options: .atomic)
        } else if let existingURL, existingURL.pathExtension == "image" {
            try fileManager.moveItem(at: existingURL, to: destination)
        }
        let reference = PaymentAttachmentReference.make(contentHash: key)
        let leaseID = UUID()
        activeLeaseIDsByReference[reference, default: []].insert(leaseID)
        return ImportedImageWrite(
            reference: reference,
            leaseID: leaseID
        )
    }

    private func validate(_ data: Data) throws -> ImageAssetFormat {
        do {
            return try ImageAssetValidator.validate(data)
        } catch let error as ImageAssetValidationError {
            switch error {
            case .invalidImage: throw StoreError.invalidImage
            case .unsupportedImageType: throw StoreError.unsupportedImageType
            case .imageTooLarge: throw StoreError.imageTooLarge
            }
        }
    }

    private func cacheKey(from reference: String) throws -> String {
        guard let key = PaymentAttachmentReference.contentHash(from: reference) else {
            throw StoreError.invalidReference
        }
        return key
    }

    private func storedImageDirectory() throws -> URL {
        let directory = storageRootURL
            .appending(path: "PaymentAttachments", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var storageRootURL: URL {
        storageRoot ?? AppConfiguration.storeURL.deletingLastPathComponent()
    }

    private func storedImageURL(key: String) throws -> URL? {
        let directory = try storedImageDirectory()
        for pathExtension in Self.storedImageExtensions {
            let candidate = directory
                .appending(path: key)
                .appendingPathExtension(pathExtension)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Earlier builds could remove a committed payment attachment during view
    /// dismissal. If the same content is still present as a user-selected icon,
    /// restore it by its content hash instead of asking the user to select it again.
    private func recoverFromLocalIconCache(key: String) throws -> URL? {
        let source = storageRootURL
            .appending(path: "UserServiceIcons", directoryHint: .isDirectory)
            .appending(path: key)
            .appendingPathExtension("image")
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        let data = try Data(contentsOf: source)
        let actualKey = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualKey == key else { return nil }
        let format = try validate(data)
        let destination = try storedImageDirectory()
            .appending(path: key)
            .appendingPathExtension(format.filenameExtension)
        if !fileManager.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: .atomic)
        }
        return destination
    }

    private func removeStoredImage(key: String) throws {
        let directory = try storedImageDirectory()
        for pathExtension in Self.storedImageExtensions {
            let candidate = directory
                .appending(path: key)
                .appendingPathExtension(pathExtension)
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            try fileManager.removeItem(at: candidate)
        }
        try? fileManager.removeItem(at: quickLookPreviewDirectory(key: key))
    }

    private func makeQuickLookPreviewURL(source: URL, key: String) throws -> URL {
        let directory = quickLookPreviewDirectory(key: key)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory
            .appending(path: "消费截图")
            .appendingPathExtension(source.pathExtension)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    private func quickLookPreviewDirectory(key: String) -> URL {
        fileManager.temporaryDirectory
            .appending(path: "Periodic", directoryHint: .isDirectory)
            .appending(path: "PaymentAttachmentPreviews", directoryHint: .isDirectory)
            .appending(path: key, directoryHint: .isDirectory)
    }
}
