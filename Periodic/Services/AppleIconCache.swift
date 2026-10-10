import CryptoKit
import Foundation

actor AppleIconCache {
    struct ImportedImageWrite: Sendable {
        var reference: String { lease.reference }
        fileprivate let key: String
        fileprivate let lease: ImageWriteLeases.Lease
    }

    enum CacheError: LocalizedError {
        case invalidURL
        case invalidReference
        case unsupportedHost
        case invalidResponse
        case invalidImage
        case unsupportedImageType
        case imageTooLarge
        case storedImageMissing

        var errorDescription: String? {
            switch self {
            case .invalidURL: AppLocalization.string("图标地址无效。")
            case .invalidReference: AppLocalization.string("已保存的图标引用无效。")
            case .unsupportedHost: AppLocalization.string("只能保存 Apple 提供的图标。")
            case .invalidResponse: AppLocalization.string("Apple 返回的图标数据无效。")
            case .invalidImage: AppLocalization.string("所选文件不是可解码的图片。")
            case .unsupportedImageType: AppLocalization.string("请选择 PNG 或 JPEG 图片。")
            case .imageTooLarge: AppLocalization.string("图标文件过大，无法保存。")
            case .storedImageMissing: AppLocalization.string("已保存的图标文件不存在。")
            }
        }
    }

    private let download: @Sendable (URL) async throws -> (Data, URLResponse)
    private let fileManager: FileManager
    private let storageRoot: URL?
    private let legacyStorageRoot: URL?
    private var imageWriteLeases = ImageWriteLeases()
    private var createdImportedReferences = Set<String>()
    private var retentionGeneration = 0
    private var retainedGenerations: [String: Int] = [:]

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        storageRoot: URL? = nil,
        legacyStorageRoot: URL? = nil,
        download: (@Sendable (URL) async throws -> (Data, URLResponse))? = nil
    ) {
        self.download = download ?? { url in try await session.data(from: url) }
        self.fileManager = fileManager
        self.storageRoot = storageRoot
        self.legacyStorageRoot = legacyStorageRoot ?? storageRoot?.appending(
            path: "LegacyAppleServiceIcons", directoryHint: .isDirectory
        )
    }

    private static let referencePrefix = StoredIconReference.Source.apple.prefix
    private static let localReferencePrefix = StoredIconReference.Source.user.prefix
    func persist(from url: URL) async throws -> String {
        let write = try await persistDraftImage(from: url)
        releaseImportedImages([write])
        return write.reference
    }

    func persistDraftImage(from url: URL) async throws -> ImportedImageWrite {
        guard url.scheme == "https" else { throw CacheError.invalidURL }
        guard let host = url.host?.lowercased(),
              host == "mzstatic.com" || host.hasSuffix(".mzstatic.com") else {
            throw CacheError.unsupportedHost
        }

        let (data, response) = try await download(url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.mimeType?.hasPrefix("image/") == true,
              !data.isEmpty else {
            throw CacheError.invalidResponse
        }
        guard data.count <= ImageAssetValidator.maximumImageSize else {
            throw CacheError.imageTooLarge
        }
        try validateImageData(data)
        let directory = try storedIconDirectory()
        var key = cacheKey(for: data)
        var destination = directory
            .appending(path: key)
            .appendingPathExtension("image")
        if fileManager.fileExists(atPath: destination.path),
           (try? Data(contentsOf: destination)) != data {
            key = cacheKey(for: data + Data(UUID().uuidString.utf8))
            destination = directory.appending(path: key).appendingPathExtension("image")
        }
        let didCreateFile = !fileManager.fileExists(atPath: destination.path)
        if didCreateFile {
            try data.write(to: destination, options: .atomic)
        }
        let reference = Self.referencePrefix + key
        if didCreateFile { createdImportedReferences.insert(reference) }
        return ImportedImageWrite(key: key, lease: imageWriteLeases.acquire(for: reference))
    }

    func persistLocalImage(from url: URL) throws -> String {
        let write = try persistDraftLocalImage(from: url)
        releaseImportedImages([write])
        return write.reference
    }

    func persistDraftLocalImage(from url: URL) throws -> ImportedImageWrite {
        let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = resourceValues.fileSize,
           fileSize > ImageAssetValidator.maximumImageSize {
            throw CacheError.imageTooLarge
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: ImageAssetValidator.maximumImageSize + 1) ?? Data()
        guard data.count <= ImageAssetValidator.maximumImageSize else {
            throw CacheError.imageTooLarge
        }
        try validateImageData(data)

        return try persistImportedImage(data)
    }

    func persistImportedImage(_ data: Data) throws -> ImportedImageWrite {
        guard data.count <= ImageAssetValidator.maximumImageSize else {
            throw CacheError.imageTooLarge
        }
        try validateImageData(data)
        let key = cacheKey(for: data)
        let destination = try storedLocalIconDirectory()
            .appending(path: key)
            .appendingPathExtension("image")
        let didCreateFile = !fileManager.fileExists(atPath: destination.path)
        if didCreateFile {
            try data.write(to: destination, options: .atomic)
        }
        let reference = Self.localReferencePrefix + key
        if didCreateFile {
            createdImportedReferences.insert(reference)
        }
        return ImportedImageWrite(
            key: key,
            lease: imageWriteLeases.acquire(for: reference)
        )
    }

    func discardImportedImages(
        _ writes: [ImportedImageWrite],
        keeping references: Set<String> = []
    ) {
        let releasedReferences = imageWriteLeases.release(writes.map(\.lease))
        let retained = Set(references.compactMap { try? canonicalReference(for: $0) })
        _ = removeStoredImages(references: releasedReferences
            .intersection(createdImportedReferences).subtracting(retained))
    }

    func releaseImportedImages(_ writes: [ImportedImageWrite]) {
        imageWriteLeases.retain(writes.map(\.lease))
        createdImportedReferences.subtract(writes.map(\.reference))
        retentionGeneration &+= 1
        for write in writes { retainedGenerations[write.reference] = retentionGeneration }
    }

    func cleanupCheckpoint() -> Int { retentionGeneration }

    func removeStoredImages(
        references: Set<String>,
        protectedSince checkpoint: Int? = nil
    ) -> Set<String> {
        var failedReferences = Set<String>()
        for reference in references {
            guard let canonical = try? canonicalReference(for: reference) else { continue }
            if let checkpoint, (retainedGenerations[canonical] ?? 0) > checkpoint {
                failedReferences.insert(reference)
                continue
            }
            guard !imageWriteLeases.hasActiveLease(for: canonical) else {
                failedReferences.insert(reference)
                continue
            }
            do {
                for url in try storedLocations(for: canonical) where
                    fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            } catch {
                guard (error as NSError).code == NSFileNoSuchFileError else {
                    failedReferences.insert(reference)
                    AppLog.persistence.error("Failed to remove an unreferenced subscription icon")
                    continue
                }
            }
            createdImportedReferences.remove(canonical)
            imageWriteLeases.forget(canonical)
            retainedGenerations.removeValue(forKey: canonical)
        }
        return failedReferences
    }

    func removeUnreferencedImages(
        keeping references: Set<String>,
        modifiedBefore cutoff: Date,
        protectedSince checkpoint: Int? = nil
    ) -> Set<String> {
        let retained = Set(references.compactMap { try? canonicalReference(for: $0) })
        var candidates = Set<String>()
        do {
            let directories = [
                (try storedIconDirectory(), Self.referencePrefix),
                (try storedLocalIconDirectory(), Self.localReferencePrefix),
                (try legacyCacheDirectory(), Self.referencePrefix),
            ]
            for (directory, prefix) in directories where
                fileManager.fileExists(atPath: directory.path) {
                let urls = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )
                for url in urls where url.pathExtension == "image" {
                    let key = url.deletingPathExtension().lastPathComponent
                    guard (try? validateCacheKey(key)) != nil,
                          let modified = try url.resourceValues(
                            forKeys: [.contentModificationDateKey]
                          ).contentModificationDate,
                          modified < cutoff else { continue }
                    candidates.insert(prefix + key)
                }
            }
        } catch {
            AppLog.persistence.error("Failed to inspect unreferenced subscription icons")
        }
        return removeStoredImages(
            references: candidates.subtracting(retained),
            protectedSince: checkpoint
        )
    }

    private func canonicalReference(for reference: String) throws -> String {
        guard let storedReference = StoredIconReference(rawValue: reference) else {
            throw CacheError.invalidReference
        }
        return storedReference.rawValue
    }

    private func storedLocations(for reference: String) throws -> [URL] {
        let isApple = reference.hasPrefix(Self.referencePrefix)
        let prefix = isApple ? Self.referencePrefix : Self.localReferencePrefix
        let key = String(reference.dropFirst(prefix.count))
        let directories = isApple
            ? [try storedIconDirectory(), try legacyCacheDirectory()]
            : [try storedLocalIconDirectory()]
        return directories.map { $0.appending(path: key).appendingPathExtension("image") }
    }

    func validateImportedImage(_ data: Data) throws {
        guard data.count <= ImageAssetValidator.maximumImageSize else {
            throw CacheError.imageTooLarge
        }
        try validateImageData(data)
    }

    func data(for reference: String) throws -> Data {
        guard let storedReference = StoredIconReference(rawValue: reference) else {
            throw CacheError.invalidReference
        }
        let key = storedReference.key
        if storedReference.source == .user {
            return try storedData(forKey: key, in: storedLocalIconDirectory())
        }
        let destination = try storedIconDirectory()
            .appending(path: key)
            .appendingPathExtension("image")
        if fileManager.fileExists(atPath: destination.path) {
            return try Data(contentsOf: destination)
        }
        let legacySource = try legacyCacheDirectory()
            .appending(path: key)
            .appendingPathExtension("image")
        guard fileManager.fileExists(atPath: legacySource.path) else {
            throw CacheError.storedImageMissing
        }
        let data = try Data(contentsOf: legacySource)
        try validateImageData(data)
        try data.write(to: destination, options: .atomic)
        return data
    }

    func prepareStoredImage(for reference: String) throws {
        let data = try data(for: reference)
        try validateImageData(data)
    }

    private func storedData(forKey key: String, in directory: URL) throws -> Data {
        let source = directory
            .appending(path: key)
            .appendingPathExtension("image")
        guard fileManager.fileExists(atPath: source.path) else {
            throw CacheError.storedImageMissing
        }
        return try Data(contentsOf: source)
    }

    private func storedIconDirectory() throws -> URL {
        let directory = storageRootURL
            .appending(path: "AppleServiceIcons", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func storedLocalIconDirectory() throws -> URL {
        let directory = storageRootURL
            .appending(path: "UserServiceIcons", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var storageRootURL: URL {
        storageRoot ?? AppConfiguration.storeURL.deletingLastPathComponent()
    }

    private func legacyCacheDirectory() throws -> URL {
        if let legacyStorageRoot { return legacyStorageRoot }
        let base = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "AppleServiceIcons", directoryHint: .isDirectory)
    }

    private func cacheKey(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func validateCacheKey(_ key: String) throws {
        guard key.count == 64, key.allSatisfy(\.isHexDigit) else {
            throw CacheError.invalidReference
        }
    }

    private func validateImageData(_ data: Data) throws {
        do {
        _ = try ImageAssetValidator.validate(data)
        } catch let error as ImageAssetValidationError {
            switch error {
            case .invalidImage: throw CacheError.invalidImage
            case .unsupportedImageType: throw CacheError.unsupportedImageType
            case .imageTooLarge: throw CacheError.imageTooLarge
            }
        }
    }
}
