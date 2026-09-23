import Foundation
import Testing
@testable import Periodic

struct AppleIconCacheTests {
    @Test func localImageIsValidatedAndCopiedIntoManagedStorage() async throws {
        let fileManager = FileManager.default
        let testDirectory = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: testDirectory) }

        let pngData = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let sourceURL = testDirectory.appending(path: "icon.png")
        try pngData.write(to: sourceURL)
        let cache = AppleIconCache(
            storageRoot: testDirectory.appending(path: "Managed", directoryHint: .isDirectory)
        )

        let reference = try await cache.persistLocalImage(from: sourceURL)
        #expect(reference.hasPrefix("user-icon:"))

        try fileManager.removeItem(at: sourceURL)
        let storedData = try await cache.data(for: reference)
        #expect(storedData == pngData)
    }
}
