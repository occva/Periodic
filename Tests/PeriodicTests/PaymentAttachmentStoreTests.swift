import CryptoKit
import Foundation
import Testing
@testable import Periodic

struct PaymentAttachmentStoreTests {
    @Test func localPNGIsValidatedDeduplicatedAndDiscarded() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sourceURL = storageRoot.appending(path: "receipt.png")
        try FileManager.default.createDirectory(
            at: storageRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        try imageData.write(to: sourceURL)
        let store = PaymentAttachmentStore(storageRoot: storageRoot)

        let first = try await store.persistLocalImage(from: sourceURL)
        let duplicate = try await store.persistLocalImage(from: sourceURL)

        #expect(first.reference == duplicate.reference)
        #expect(try await store.data(for: first.reference) == imageData)
        let previewURL = try await store.previewURL(for: first.reference)
        #expect(previewURL.pathExtension == "png")
        #expect(previewURL.lastPathComponent == "消费截图.png")
        #expect(try Data(contentsOf: previewURL) == imageData)
        try Data("edited preview".utf8).write(to: previewURL, options: .atomic)
        #expect(try await store.data(for: first.reference) == imageData)
        let refreshedPreviewURL = try await store.previewURL(for: first.reference)
        #expect(try Data(contentsOf: refreshedPreviewURL) == imageData)
        let previewURLs = try await store.previewURLs(
            for: [duplicate.reference, first.reference]
        )
        #expect(previewURLs.map(\.path) == [refreshedPreviewURL.path, refreshedPreviewURL.path])

        await store.discardImportedImages(
            [first],
            keeping: [duplicate.reference]
        )
        #expect(try await store.data(for: first.reference) == imageData)

        await store.discardImportedImages([first, duplicate])
        await #expect(throws: PaymentAttachmentStore.StoreError.self) {
            try await store.data(for: first.reference)
        }
    }

    @Test func nonImageFileIsRejected() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sourceURL = storageRoot.appending(path: "not-an-image.png")
        try FileManager.default.createDirectory(
            at: storageRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        try Data("not an image".utf8).write(to: sourceURL)
        let store = PaymentAttachmentStore(storageRoot: storageRoot)

        await #expect(throws: PaymentAttachmentStore.StoreError.self) {
            try await store.persistLocalImage(from: sourceURL)
        }
    }

    @Test func activeDraftLeaseProtectsImageFromConcurrentCleanup() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let store = PaymentAttachmentStore(storageRoot: storageRoot)
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let write = try await store.persistImportedImage(imageData)

        let pendingCleanup = await store.removeStoredImages(references: [write.reference])

        #expect(pendingCleanup == [write.reference])
        #expect(try await store.data(for: write.reference) == imageData)

        await store.discardImportedImages([write])
        await #expect(throws: PaymentAttachmentStore.StoreError.self) {
            try await store.data(for: write.reference)
        }
    }

    @Test func committedImageSurvivesStoreRecreationAndStartupGracePeriod() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let initialStore = PaymentAttachmentStore(storageRoot: storageRoot)
        let write = try await initialStore.persistImportedImage(imageData)

        await initialStore.releaseImportedImages([write])

        let reopenedStore = PaymentAttachmentStore(storageRoot: storageRoot)
        _ = await reopenedStore.removeUnreferencedImages(
            keeping: [],
            modifiedBefore: Date().addingTimeInterval(-24 * 60 * 60)
        )
        #expect(try await reopenedStore.data(for: write.reference) == imageData)

        let storedHash = try #require(
            PaymentAttachmentReference.contentHash(from: write.reference)
        )
        let storedURL = storageRoot
            .appending(path: "PaymentAttachments", directoryHint: .isDirectory)
            .appending(path: storedHash)
            .appendingPathExtension("png")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: storedURL.path
        )
        _ = await reopenedStore.removeUnreferencedImages(
            keeping: [write.reference],
            modifiedBefore: .now
        )
        #expect(try await reopenedStore.data(for: write.reference) == imageData)
    }

    @Test func missingAttachmentRecoversFromIdenticalLocalIconContent() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let hash = SHA256.hash(data: imageData)
            .map { String(format: "%02x", $0) }
            .joined()
        let iconDirectory = storageRoot
            .appending(path: "UserServiceIcons", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: iconDirectory,
            withIntermediateDirectories: true
        )
        try imageData.write(
            to: iconDirectory.appending(path: hash).appendingPathExtension("image")
        )
        let store = PaymentAttachmentStore(storageRoot: storageRoot)
        let reference = PaymentAttachmentReference.make(contentHash: hash)

        #expect(try await store.data(for: reference) == imageData)
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
