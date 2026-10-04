import Foundation
import Testing
@testable import Periodic

struct CloudAssetRepositoryTests {
    @Test func rollbackRemovesNewlyMaterializedAttachment() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try imageData()
        let metadata = assetMetadata(for: data)
        let reference = PaymentAttachmentReference.make(
            contentHash: metadata.contentHash
        )
        let stagingRoot = root.appending(
            path: "CloudAssetStaging",
            directoryHint: .isDirectory
        )
        let initialStager = CloudImageAssetStager(stagingRoot: stagingRoot)
        let staged = try await initialStager.stage(
            data: data,
            expectedContentHash: metadata.contentHash
        )
        let attachmentStore = PaymentAttachmentStore(storageRoot: root)
        let repository = CloudAssetRepository(
            iconCache: AppleIconCache(storageRoot: root),
            paymentAttachmentStore: attachmentStore,
            stager: CloudImageAssetStager(stagingRoot: stagingRoot)
        )

        let materialized = try await repository.commitStagedDownload(
            reference: reference,
            metadata: metadata
        )
        #expect(try await attachmentStore.data(for: reference) == data)

        await repository.rollback(materialized)

        await #expect(throws: PaymentAttachmentStore.StoreError.self) {
            try await attachmentStore.data(for: reference)
        }
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test func rollbackRestoresStableAppleIconContent() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let previousData = try imageData()
        let replacementData = previousData + Data([0])
        let metadata = assetMetadata(for: replacementData)
        let reference = AppleIconCache.referencePrefix
            + String(repeating: "a", count: 64)
        let iconCache = AppleIconCache(storageRoot: root)
        try await iconCache.persistCloudImage(
            previousData,
            reference: reference
        )
        let stagingRoot = root.appending(
            path: "CloudAssetStaging",
            directoryHint: .isDirectory
        )
        let initialStager = CloudImageAssetStager(stagingRoot: stagingRoot)
        let staged = try await initialStager.stage(
            data: replacementData,
            expectedContentHash: metadata.contentHash
        )
        let repository = CloudAssetRepository(
            iconCache: iconCache,
            paymentAttachmentStore: PaymentAttachmentStore(storageRoot: root),
            stager: CloudImageAssetStager(stagingRoot: stagingRoot)
        )

        let materialized = try await repository.commitStagedDownload(
            reference: reference,
            metadata: metadata
        )
        #expect(try await iconCache.data(for: reference) == replacementData)

        await repository.rollback(materialized)

        #expect(try await iconCache.data(for: reference) == previousData)
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test func finalizeKeepsMaterializedFileAndReleasesStaging() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try imageData()
        let metadata = assetMetadata(for: data)
        let reference = PaymentAttachmentReference.make(
            contentHash: metadata.contentHash
        )
        let stagingRoot = root.appending(
            path: "CloudAssetStaging",
            directoryHint: .isDirectory
        )
        let initialStager = CloudImageAssetStager(stagingRoot: stagingRoot)
        let staged = try await initialStager.stage(
            data: data,
            expectedContentHash: metadata.contentHash
        )
        let attachmentStore = PaymentAttachmentStore(storageRoot: root)
        let repository = CloudAssetRepository(
            iconCache: AppleIconCache(storageRoot: root),
            paymentAttachmentStore: attachmentStore,
            stager: CloudImageAssetStager(stagingRoot: stagingRoot)
        )

        let materialized = try await repository.commitStagedDownload(
            reference: reference,
            metadata: metadata
        )
        await repository.finalize(materialized)

        #expect(try await attachmentStore.data(for: reference) == data)
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func imageData() throws -> Data {
        try #require(Data(base64Encoded: Self.onePixelPNG))
    }

    private func assetMetadata(for data: Data) -> CloudAssetMetadata {
        CloudAssetMetadata(
            contentHash: CloudImageAssetStager.contentHash(of: data),
            format: .png,
            byteCount: data.count
        )
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
