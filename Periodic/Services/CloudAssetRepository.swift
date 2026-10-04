import Foundation

actor CloudAssetRepository {
    struct UploadAsset: Sendable {
        let reference: String
        let stagedImage: CloudImageAssetStager.StagedImage
    }

    struct DownloadAsset: Sendable {
        let reference: String
        let stagedImage: CloudImageAssetStager.StagedImage
    }

    struct MaterializedDownload: Sendable {
        fileprivate let asset: DownloadAsset
        fileprivate let previousData: Data?
        fileprivate let didWriteManagedFile: Bool
    }

    enum RepositoryError: LocalizedError, Equatable {
        case invalidReference
        case removalFailed

        var errorDescription: String? {
            switch self {
            case .invalidReference:
                "iCloud 图片引用无效。"
            case .removalFailed:
                "无法移除已从 iCloud 删除的图片。"
            }
        }
    }

    private let iconCache: AppleIconCache
    private let paymentAttachmentStore: PaymentAttachmentStore
    private let stager: CloudImageAssetStager

    init(
        iconCache: AppleIconCache,
        paymentAttachmentStore: PaymentAttachmentStore,
        stager: CloudImageAssetStager
    ) {
        self.iconCache = iconCache
        self.paymentAttachmentStore = paymentAttachmentStore
        self.stager = stager
    }

    func stageUpload(reference: String) async throws -> UploadAsset {
        let data = try await data(for: reference)
        let staged = try await stager.stage(
            data: data,
            expectedContentHash: expectedContentHash(
                reference: reference,
                data: data
            )
        )
        return UploadAsset(reference: reference, stagedImage: staged)
    }

    func metadata(reference: String) async throws -> CloudAssetMetadata {
        let data = try await data(for: reference)
        return try metadata(reference: reference, data: data)
    }

    func metadataIfPresent(
        reference: String
    ) async throws -> CloudAssetMetadata? {
        do {
            return try await metadata(reference: reference)
        } catch {
            if let cacheError = error as? AppleIconCache.CacheError,
               cacheError == .storedImageMissing {
                return nil
            }
            if let storeError = error as? PaymentAttachmentStore.StoreError,
               storeError == .storedImageMissing {
                return nil
            }
            throw error
        }
    }

    func stageDownload(
        reference: String,
        fileURL: URL,
        metadata: CloudAssetMetadata
    ) async throws -> DownloadAsset {
        guard Self.isSupportedReference(reference),
              Self.contentHash(encodedIn: reference)
                .map({ $0 == metadata.contentHash }) ?? true else {
            throw RepositoryError.invalidReference
        }
        let data = try Data(contentsOf: fileURL)
        guard data.count == metadata.byteCount else {
            throw CloudImageAssetStager.StagingError.hashMismatch
        }
        let staged = try await stager.stage(
            data: data,
            expectedContentHash: metadata.contentHash
        )
        guard staged.format == metadata.format else {
            await stager.release([staged])
            throw CloudImageAssetStager.StagingError.unsupportedImageType
        }
        return DownloadAsset(reference: reference, stagedImage: staged)
    }

    func commitStagedDownload(
        reference: String,
        metadata: CloudAssetMetadata
    ) async throws -> MaterializedDownload {
        let staged = try await stager.acquireExisting(metadata: metadata)
        let asset = DownloadAsset(reference: reference, stagedImage: staged)
        do {
            let previousData = try await dataIfPresent(reference: reference)
            if let previousData {
                let existing = try self.metadata(
                    reference: reference,
                    data: previousData
                )
                if existing == metadata {
                    return MaterializedDownload(
                        asset: asset,
                        previousData: nil,
                        didWriteManagedFile: false
                    )
                }
                guard Self.contentHash(encodedIn: reference) == nil else {
                    throw CloudImageAssetStager.StagingError.hashMismatch
                }
            }
            let data = try await stager.data(for: staged)
            try await persist(data: data, reference: reference)
            return MaterializedDownload(
                asset: asset,
                previousData: previousData,
                didWriteManagedFile: true
            )
        } catch {
            await stager.release([staged])
            throw error
        }
    }

    func finalize(_ materialized: MaterializedDownload) async {
        await stager.release([materialized.asset.stagedImage])
    }

    func rollback(_ materialized: MaterializedDownload) async {
        if materialized.didWriteManagedFile {
            if let previousData = materialized.previousData {
                do {
                    try await persist(
                        data: previousData,
                        reference: materialized.asset.reference
                    )
                } catch {
                    AppLog.persistence.error(
                        "Failed to restore a cloud image after rollback"
                    )
                }
            } else {
                await removeManagedFile(
                    reference: materialized.asset.reference
                )
            }
        }
        await finalize(materialized)
    }

    func delete(reference: String) async throws {
        guard Self.isSupportedReference(reference) else {
            throw RepositoryError.invalidReference
        }
        let failedReferences: Set<String>
        if AppleIconCache.isStoredReference(reference) {
            failedReferences = await iconCache.removeStoredImages(
                references: [reference]
            )
        } else {
            failedReferences = await paymentAttachmentStore
                .removeStoredImages(references: [reference])
        }
        guard failedReferences.isEmpty else {
            throw RepositoryError.removalFailed
        }
    }

    func release(_ assets: [UploadAsset]) async {
        await stager.release(assets.map(\.stagedImage))
    }

    func release(_ assets: [DownloadAsset]) async {
        await stager.release(assets.map(\.stagedImage))
    }

    static func isSupportedReference(_ reference: String) -> Bool {
        AppleIconCache.isStoredReference(reference)
            || PaymentAttachmentReference.isValid(reference)
    }

    static func contentHash(encodedIn reference: String) -> String? {
        if reference.hasPrefix(AppleIconCache.localReferencePrefix) {
            let hash = String(
                reference.dropFirst(
                    AppleIconCache.localReferencePrefix.count
                )
            )
            return hash.count == 64 && hash.allSatisfy(\.isHexDigit)
                ? hash.lowercased()
                : nil
        }
        return PaymentAttachmentReference.contentHash(from: reference)?
            .lowercased()
    }

    private func data(for reference: String) async throws -> Data {
        if AppleIconCache.isStoredReference(reference) {
            return try await iconCache.data(for: reference)
        }
        if PaymentAttachmentReference.isValid(reference) {
            return try await paymentAttachmentStore.data(for: reference)
        }
        throw RepositoryError.invalidReference
    }

    private func dataIfPresent(reference: String) async throws -> Data? {
        do {
            return try await data(for: reference)
        } catch {
            if let cacheError = error as? AppleIconCache.CacheError,
               cacheError == .storedImageMissing {
                return nil
            }
            if let storeError = error as? PaymentAttachmentStore.StoreError,
               storeError == .storedImageMissing {
                return nil
            }
            throw error
        }
    }

    private func metadata(
        reference: String,
        data: Data
    ) throws -> CloudAssetMetadata {
        let format = try ImageAssetValidator.validate(data)
        let contentHash = CloudImageAssetStager.contentHash(of: data)
        let expectedHash = try expectedContentHash(
            reference: reference,
            data: data
        )
        guard contentHash == expectedHash else {
            throw CloudImageAssetStager.StagingError.hashMismatch
        }
        return CloudAssetMetadata(
            contentHash: contentHash,
            format: format,
            byteCount: data.count
        )
    }

    private func persist(data: Data, reference: String) async throws {
        if AppleIconCache.isStoredReference(reference) {
            try await iconCache.persistCloudImage(data, reference: reference)
        } else if PaymentAttachmentReference.isValid(reference) {
            try await paymentAttachmentStore.persistCloudImage(
                data,
                reference: reference
            )
        } else {
            throw RepositoryError.invalidReference
        }
    }

    private func removeManagedFile(reference: String) async {
        if AppleIconCache.isStoredReference(reference) {
            _ = await iconCache.removeStoredImages(references: [reference])
        } else if PaymentAttachmentReference.isValid(reference) {
            _ = await paymentAttachmentStore.removeStoredImages(
                references: [reference]
            )
        }
    }

    private func expectedContentHash(
        reference: String,
        data: Data
    ) throws -> String {
        if let hash = Self.contentHash(encodedIn: reference) {
            return hash
        }
        guard reference.hasPrefix(AppleIconCache.referencePrefix) else {
            throw RepositoryError.invalidReference
        }
        return CloudImageAssetStager.contentHash(of: data)
    }
}
