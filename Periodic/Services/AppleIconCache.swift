import CryptoKit
import Foundation

actor AppleIconCache {
    enum CacheError: LocalizedError {
        case invalidURL
        case invalidReference
        case unsupportedHost
        case invalidResponse
        case imageTooLarge
        case storedImageMissing

        var errorDescription: String? {
            switch self {
            case .invalidURL: "图标地址无效。"
            case .invalidReference: "已保存的图标引用无效。"
            case .unsupportedHost: "只能保存 Apple 提供的图标。"
            case .invalidResponse: "Apple 返回的图标数据无效。"
            case .imageTooLarge: "图标文件超过 10 MB，无法保存。"
            case .storedImageMissing: "已保存的图标文件不存在。"
            }
        }
    }

    private let session: URLSession
    private let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    private static let referencePrefix = "apple-icon:"

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
        guard data.count <= 10 * 1_024 * 1_024 else {
            throw CacheError.imageTooLarge
        }
        let key = cacheKey(for: url.absoluteString)
        let destination = try storedIconDirectory()
            .appending(path: key)
            .appendingPathExtension("image")
        try data.write(to: destination, options: .atomic)
        return Self.referencePrefix + key
    }

    func data(for reference: String) throws -> Data {
        if reference.hasPrefix(Self.referencePrefix) {
            let key = String(reference.dropFirst(Self.referencePrefix.count))
            guard key.count == 64, key.allSatisfy(\.isHexDigit) else {
                throw CacheError.invalidReference
            }
            return try storedData(forKey: key)
        }

        // Earlier development builds stored the Apple URL and cached the bytes.
        // Migrate an existing cached file without issuing a background request.
        guard let url = URL(string: reference), url.scheme == "https",
              let host = url.host?.lowercased(),
              host == "mzstatic.com" || host.hasSuffix(".mzstatic.com") else {
            throw CacheError.invalidReference
        }
        let key = cacheKey(for: reference)
        if let data = try? storedData(forKey: key) {
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

    private func storedData(forKey key: String) throws -> Data {
        let source = try storedIconDirectory()
            .appending(path: key)
            .appendingPathExtension("image")
        guard fileManager.fileExists(atPath: source.path) else {
            throw CacheError.storedImageMissing
        }
        return try Data(contentsOf: source)
    }

    private func storedIconDirectory() throws -> URL {
        let directory = AppConfiguration.storeURL
            .deletingLastPathComponent()
            .appending(path: "AppleServiceIcons", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
        SHA256.hash(data: Data(urlString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
