import Foundation
import Testing
@testable import Periodic

struct AppleIconCacheTests {
    @MainActor
    @Test func inMemoryServicesUseAnIsolatedTemporaryIconRoot() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let firstRoot = try #require(
            AppServices.defaultIconStorageRoot(
                useMemoryStore: true,
                temporaryDirectory: temporaryDirectory
            )
        )
        let secondRoot = try #require(
            AppServices.defaultIconStorageRoot(
                useMemoryStore: true,
                temporaryDirectory: temporaryDirectory
            )
        )

        #expect(firstRoot.deletingLastPathComponent() == secondRoot.deletingLastPathComponent())
        #expect(firstRoot != secondRoot)
        #expect(firstRoot.path.hasPrefix(temporaryDirectory.path))
        #expect(
            AppServices.defaultIconStorageRoot(
                useMemoryStore: false,
                temporaryDirectory: temporaryDirectory
            ) == nil
        )
    }

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

    @Test func localSelectionProtectsImageFromConcurrentImportRollback() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let sourceURL = storageRoot.appending(path: "icon.png")
        try imageData.write(to: sourceURL)
        let cache = AppleIconCache(storageRoot: storageRoot)
        let importWrite = try await cache.persistImportedImage(imageData)
        let editorReference = try await cache.persistLocalImage(from: sourceURL)

        await cache.discardImportedImages([importWrite])

        #expect(importWrite.reference == editorReference)
        #expect(try await cache.data(for: editorReference) == imageData)
    }

    @Test func concurrentImportsKeepSharedImageUntilLastOwnerDiscards() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let cache = AppleIconCache(storageRoot: storageRoot)
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let first = try await cache.persistImportedImage(imageData)
        let second = try await cache.persistImportedImage(imageData)

        await cache.discardImportedImages([first])
        #expect(try await cache.data(for: second.reference) == imageData)
        await cache.discardImportedImages([second])
        await #expect(throws: AppleIconCache.CacheError.self) {
            try await cache.data(for: second.reference)
        }
    }

    @Test func committedIconSurvivesOlderRollbackAndRemainsExplicitlyRemovable() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let cache = AppleIconCache(storageRoot: storageRoot)
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let pendingImport = try await cache.persistImportedImage(imageData)
        let committedImport = try await cache.persistImportedImage(imageData)

        await cache.releaseImportedImages([committedImport])
        await cache.discardImportedImages([pendingImport])

        #expect(try await cache.data(for: committedImport.reference) == imageData)
        #expect(await cache.removeStoredImages(references: [committedImport.reference]).isEmpty)
        let replacement = try await cache.persistImportedImage(imageData)
        await cache.discardImportedImages([pendingImport])
        #expect(try await cache.data(for: replacement.reference) == imageData)
        await cache.discardImportedImages([replacement])
        await #expect(throws: AppleIconCache.CacheError.self) {
            try await cache.data(for: replacement.reference)
        }
    }

    @Test func storedImageRemovalReportsFailuresForRetry() async throws {
        let fileManager = FileManager.default
        let testDirectory = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: testDirectory) }
        let invalidStorageRoot = testDirectory.appending(path: "not-a-directory")
        try Data("occupied".utf8).write(to: invalidStorageRoot)
        let cache = AppleIconCache(storageRoot: invalidStorageRoot)
        let reference = "user-icon:" + String(repeating: "a", count: 64)

        let failures = await cache.removeStoredImages(references: [reference])

        #expect(failures == [reference])
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
