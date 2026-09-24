import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor AppleIconCache {
    struct ImportedImageWrite: Sendable {
        let reference: String
        fileprivate let key: String
        fileprivate let didCreateFile: Bool
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

    private let session: URLSession
    private let fileManager: FileManager
    private let storageRoot: URL?

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        storageRoot: URL? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.storageRoot = storageRoot
    }

    private static let referencePrefix = "apple-icon:"
    private static let localReferencePrefix = "user-icon:"
    private static let maximumImageSize = 10 * 1_024 * 1_024
    private static let maximumPixelCount = 32_000_000

    func persist(from url: URL) async throws -> String {
        guard url.scheme == "https" else { throw CacheError.invalidURL }
        guard let host = url.host?.lowercased(),
              host == "mzstatic.com" || host.hasSuffix(".mzstatic.com") else {
            throw CacheError.unsupportedHost
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.mimeType?.hasPrefix("image/") == true,
              !data.isEmpty else {
            throw CacheError.invalidResponse
        }
        guard data.count <= Self.maximumImageSize else {
            throw CacheError.imageTooLarge
        }
        try validateImageData(data)
        let key = cacheKey(for: url.absoluteString)
        let destination = try storedIconDirectory()
            .appending(path: key)
            .appendingPathExtension("image")
        try data.write(to: destination, options: .atomic)
        return Self.referencePrefix + key
    }

    func persistLocalImage(from url: URL) throws -> String {
        let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = resourceValues.fileSize,
           fileSize > Self.maximumImageSize {
            throw CacheError.imageTooLarge
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumImageSize + 1) ?? Data()
        guard data.count <= Self.maximumImageSize else {
            throw CacheError.imageTooLarge
        }
        try validateImageData(data)

        let key = cacheKey(for: data)
        let destination = try storedLocalIconDirectory()
            .appending(path: key)
            .appendingPathExtension("image")
        if !fileManager.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: .atomic)
        }
        return Self.localReferencePrefix + key
    }

    func persistImportedImage(_ data: Data) throws -> ImportedImageWrite {
        guard data.count <= Self.maximumImageSize else {
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
        return ImportedImageWrite(
            reference: Self.localReferencePrefix + key,
            key: key,
            didCreateFile: didCreateFile
        )
    }

    func discardImportedImages(
        _ writes: [ImportedImageWrite],
        keeping references: Set<String> = []
    ) {
        for write in writes where write.didCreateFile && !references.contains(write.reference) {
            let url: URL
            do {
                url = try storedLocalIconDirectory()
                    .appending(path: write.key)
                    .appendingPathExtension("image")
                try fileManager.removeItem(at: url)
            } catch {
                if (error as NSError).code != NSFileNoSuchFileError {
                    AppLog.persistence.error("Failed to remove an unreferenced imported icon")
                }
            }
        }
    }

    func validateImportedImage(_ data: Data) throws {
        guard data.count <= Self.maximumImageSize else {
            throw CacheError.imageTooLarge
        }
        try validateImageData(data)
    }

    func data(for reference: String) throws -> Data {
        if reference.hasPrefix(Self.referencePrefix) {
            let key = String(reference.dropFirst(Self.referencePrefix.count))
            try validateCacheKey(key)
            return try storedData(forKey: key, in: storedIconDirectory())
        }
        if reference.hasPrefix(Self.localReferencePrefix) {
            let key = String(reference.dropFirst(Self.localReferencePrefix.count))
            try validateCacheKey(key)
            return try storedData(forKey: key, in: storedLocalIconDirectory())
        }

        // Earlier development builds stored the Apple URL and cached the bytes.
        // Migrate an existing cached file without issuing a background request.
        guard let url = URL(string: reference), url.scheme == "https",
              let host = url.host?.lowercased(),
              host == "mzstatic.com" || host.hasSuffix(".mzstatic.com") else {
            throw CacheError.invalidReference
        }
        let key = cacheKey(for: reference)
        if let data = try? storedData(forKey: key, in: storedIconDirectory()) {
            return data
        }
        let legacySource = try legacyCacheDirectory()
            .appending(path: key)
            .appendingPathExtension("image")
        guard fileManager.fileExists(atPath: legacySource.path) else {
            throw CacheError.storedImageMissing
        }
        let data = try Data(contentsOf: legacySource)
        let destination = try storedIconDirectory()
            .appending(path: key)
            .appendingPathExtension("image")
        try data.write(to: destination, options: .atomic)
        return data
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
        let base = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "AppleServiceIcons", directoryHint: .isDirectory)
    }

    private func cacheKey(for urlString: String) -> String {
        cacheKey(for: Data(urlString.utf8))
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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw CacheError.invalidImage
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0,
              width <= Self.maximumPixelCount / height else {
            throw CacheError.imageTooLarge
        }
        guard let typeIdentifier = CGImageSourceGetType(source) as String?,
              typeIdentifier == UTType.png.identifier
                || typeIdentifier == UTType.jpeg.identifier else {
            throw CacheError.unsupportedImageType
        }
    }
}
