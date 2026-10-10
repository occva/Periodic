import Foundation
import CryptoKit
import Testing
@testable import Periodic

struct AppleIconCacheTests {
    @Test func selectingUpdatedAppleImageStagesNewBytesWithoutChangingTheSavedImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try #require(Data(base64Encoded: Self.onePixelPNG))
        let updatedImage = image + Data([0])
        let url = try #require(URL(string: "https://example.mzstatic.com/unchanged.png"))
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"]
        ))
        let firstCache = AppleIconCache(storageRoot: directory, download: { _ in (image, response) })
        let savedReference = try await firstCache.persist(from: url)
        let cache = AppleIconCache(storageRoot: directory, download: { _ in (updatedImage, response) })

        let draft = try await cache.persistDraftImage(from: url)

        #expect(draft.reference != savedReference)
        #expect(try await cache.data(for: draft.reference) == updatedImage)
        #expect(try await cache.data(for: savedReference) == image)
        await cache.discardImportedImages([draft], keeping: [savedReference])
        #expect(try await cache.data(for: savedReference) == image)
        await #expect(throws: AppleIconCache.CacheError.self) { try await cache.data(for: draft.reference) }
    }

    @Test func selectingAppleImageRepairsACorruptedStoredFileWithoutOverwritingItInTheDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try #require(Data(base64Encoded: Self.onePixelPNG))
        let url = try #require(URL(string: "https://example.mzstatic.com/corrupt.png"))
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"]
        ))
        let cache = AppleIconCache(storageRoot: directory, download: { _ in (image, response) })
        let originalReference = try await cache.persist(from: url)
        let key = try #require(StoredIconReference(rawValue: originalReference)).key
        let file = directory.appending(path: "AppleServiceIcons").appending(path: key + ".image")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: file)

        let repaired = try await cache.persistDraftImage(from: url)

        #expect(repaired.reference != originalReference)
        #expect(try Data(contentsOf: file) == corrupt)
        #expect(try await cache.data(for: repaired.reference) == image)
        await cache.releaseImportedImages([repaired])
        #expect(try await cache.data(for: repaired.reference) == image)
    }

    @Test func selectingIdenticalAppleBytesRepairsACorruptedContentFileAndProtectsCommittedDrafts() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try #require(Data(base64Encoded: Self.onePixelPNG))
        let url = try #require(URL(string: "https://example.mzstatic.com/content-corrupt.png"))
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"]
        ))
        let cache = AppleIconCache(storageRoot: directory, download: { _ in (image, response) })
        let original = try await cache.persist(from: url)
        let key = try #require(StoredIconReference(rawValue: original)).key
        let file = directory.appending(path: "AppleServiceIcons").appending(path: key + ".image")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: file)

        let replacement = try await cache.persistDraftImage(from: url)
        #expect(replacement.reference != original)
        #expect(try Data(contentsOf: file) == corrupt)
        #expect(try await cache.data(for: replacement.reference) == image)
        await cache.releaseImportedImages([replacement])
        let anotherDraft = try await cache.persistDraftImage(from: url)
        await cache.discardImportedImages([anotherDraft], keeping: [original, replacement.reference])
        #expect(try await cache.data(for: replacement.reference) == image)
    }

    @Test func explicitStorageRootKeepsLegacyImagesInTheSameStorageScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appending(path: "LegacyAppleServiceIcons")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let reference = "https://example.mzstatic.com/" + UUID().uuidString + ".png"
        let key = SHA256.hash(data: Data(reference.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        try data.write(to: legacy.appending(path: key).appendingPathExtension("image"))
        let cache = AppleIconCache(storageRoot: directory)

        #expect(try await cache.data(for: reference) == data)
        #expect(await cache.removeStoredImages(references: [reference]).isEmpty)
        await #expect(throws: AppleIconCache.CacheError.self) {
            try await cache.data(for: reference)
        }
    }

    @Test func cleanupDoesNotDeleteAnIconCommittedAfterTheReferenceCheck() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppleIconCache(storageRoot: directory)
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        let write = try await cache.persistImportedImage(data)
        let checkpoint = await cache.cleanupCheckpoint()
        await cache.releaseImportedImages([write])
        let failures = await cache.removeStoredImages(
            references: [write.reference], protectedSince: checkpoint
        )
        #expect(failures == [write.reference])
        #expect(try await cache.data(for: write.reference) == data)
    }

    @Test func cancelledDraftKeepsAnotherDraftsIconUntilItsOwnerDiscards() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppleIconCache(storageRoot: directory)
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        let source = directory.appending(path: "source.png")
        try data.write(to: source)
        let first = try await cache.persistDraftLocalImage(from: source)
        let second = try await cache.persistDraftLocalImage(from: source)
        await cache.discardImportedImages([first])
        #expect(try await cache.data(for: second.reference) == data)
        await cache.discardImportedImages([second])
        await #expect(throws: AppleIconCache.CacheError.self) {
            try await cache.data(for: second.reference)
        }
    }

    @Test func orphanScanProtectsReferencedAndLeasedIcons() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppleIconCache(
            storageRoot: directory,
            legacyStorageRoot: directory.appending(path: "Legacy")
        )
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        let write = try await cache.persistImportedImage(data)
        _ = await cache.removeUnreferencedImages(keeping: [], modifiedBefore: .distantFuture)
        #expect(try await cache.data(for: write.reference) == data)
        await cache.releaseImportedImages([write])
        _ = await cache.removeUnreferencedImages(
            keeping: [write.reference], modifiedBefore: .distantFuture
        )
        #expect(try await cache.data(for: write.reference) == data)
        _ = await cache.removeUnreferencedImages(keeping: [], modifiedBefore: .distantFuture)
        await #expect(throws: AppleIconCache.CacheError.self) {
            try await cache.data(for: write.reference)
        }
    }

    @Test func legacyAppleReferenceIsPreservedByScanAndRemovedFromBothLocations() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appending(path: "Legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let reference = "https://example.mzstatic.com/legacy-icon.png"
        let key = SHA256.hash(data: Data(reference.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let source = legacy.appending(path: key).appendingPathExtension("image")
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        try data.write(to: source)
        let cache = AppleIconCache(storageRoot: directory, legacyStorageRoot: legacy)
        #expect(try await cache.data(for: reference) == data)
        _ = await cache.removeUnreferencedImages(
            keeping: [reference], modifiedBefore: .distantFuture
        )
        #expect(try await cache.data(for: reference) == data)
        #expect(await cache.removeStoredImages(references: [reference]).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        await #expect(throws: AppleIconCache.CacheError.self) {
            try await cache.data(for: reference)
        }
    }

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
