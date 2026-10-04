import Foundation
import Observation

@MainActor
@Observable
final class CloudSyncCoordinator {
    enum CoordinatorError: LocalizedError {
        case unavailable
        case alreadyEnabled
        case notEnabled

        var errorDescription: String? {
            switch self {
            case .unavailable:
                AppLocalization.string("此构建未包含 iCloud 能力。请先为 Periodic 配置 Apple Developer Team、iCloud 容器和 CloudKit entitlement。")
            case .alreadyEnabled:
                AppLocalization.string("iCloud 同步已经启用。")
            case .notEnabled:
                AppLocalization.string("iCloud 同步尚未启用。")
            }
        }
    }

    private(set) var snapshot: CloudSyncPresentationSnapshot

    @ObservationIgnored private let transport: (any CloudSyncTransport)?
    @ObservationIgnored private let bootstrapStore: SyncBootstrapStore?
    @ObservationIgnored private let statusStore: CloudSyncStatusStore?
    @ObservationIgnored private let remoteChangeApplier:
        SyncRemoteChangeApplier?
    @ObservationIgnored private let dataExchange: DataExchangeService?
    @ObservationIgnored private let metadataStore: CloudSyncMetadataStore?
    @ObservationIgnored private let descriptorRepository:
        DatasetDescriptorRepository?
    @ObservationIgnored private let safetySnapshotService:
        CloudSyncSafetySnapshotService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var descriptor: DatasetDescriptor
    @ObservationIgnored private var isPrepared = false
    @ObservationIgnored private var isOperationRunning = false
    @ObservationIgnored private var dataChangeHandler: (() -> Void)?

    init(
        transport: (any CloudSyncTransport)?,
        bootstrapStore: SyncBootstrapStore?,
        statusStore: CloudSyncStatusStore?,
        remoteChangeApplier: SyncRemoteChangeApplier? = nil,
        dataExchange: DataExchangeService?,
        metadataStore: CloudSyncMetadataStore?,
        descriptorRepository: DatasetDescriptorRepository?,
        safetySnapshotService: CloudSyncSafetySnapshotService,
        descriptor: DatasetDescriptor,
        defaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.bootstrapStore = bootstrapStore
        self.statusStore = statusStore
        self.remoteChangeApplier = remoteChangeApplier
        self.dataExchange = dataExchange
        self.metadataStore = metadataStore
        self.descriptorRepository = descriptorRepository
        self.safetySnapshotService = safetySnapshotService
        self.descriptor = descriptor
        self.defaults = defaults
        let enabled = defaults.bool(
            forKey: PreferenceKey.iCloudSyncEnabled
        )
        snapshot = CloudSyncPresentationSnapshot(
            isEnabled: enabled,
            phase: enabled ? .checking : .disabled,
            localSummary: nil,
            queue: .empty,
            conflicts: [],
            lastSuccessfulSyncAt: defaults.object(
                forKey: PreferenceKey.iCloudLastSuccessfulSyncAt
            ) as? Date,
            lastSafetySnapshotURL: defaults.string(
                forKey: PreferenceKey.iCloudLastSafetySnapshotPath
            ).map { URL(fileURLWithPath: $0) },
            errorMessage: nil
        )
    }

    var isBusy: Bool {
        isOperationRunning
            || snapshot.phase == .checking
            || snapshot.phase == .preparing
            || snapshot.phase == .syncing
    }

    func prepareIfEnabled() async {
        guard snapshot.isEnabled, !isPrepared, !isOperationRunning else {
            return
        }
        isPrepared = true
        isOperationRunning = true
        update(phase: .checking, errorMessage: nil)
        defer { isOperationRunning = false }
        do {
            let dependencies = try requiredDependencies()
            _ = try await dependencies.bootstrapStore
                .bootstrapExistingRecords()
            await configureRemoteChangeHandler(
                on: dependencies.transport
            )
            try await dependencies.transport.start(
                automaticallySync: true
            )
            try await persistDescriptor(
                storageKind: .iCloud,
                lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt
            )
            try await performSync(
                transport: dependencies.transport
            )
        } catch {
            update(
                phase: phase(for: await transport?.status()),
                errorMessage: userMessage(for: error)
            )
            await refreshQueue()
        }
    }

    func previewEnablement() async throws -> CloudEnablementPreview {
        guard !snapshot.isEnabled else {
            throw CoordinatorError.alreadyEnabled
        }
        guard !isOperationRunning else {
            throw DatasetAccessError.maintenanceInProgress
        }
        isOperationRunning = true
        update(phase: .checking, errorMessage: nil)
        defer { isOperationRunning = false }
        do {
            let dependencies = try requiredDependencies()
            try await dependencies.transport.checkAvailability()
            let remoteSummary = CloudSyncDataSummary(
                remoteInventory: try await dependencies.transport
                    .previewRemoteInventory()
            )
            let summary = try await localSummary(
                dataExchange: dependencies.dataExchange,
                includesPreparedPackage: false
            )
            update(
                phase: .disabled,
                localSummary: summary,
                errorMessage: nil
            )
            return CloudEnablementPreview(
                localSummary: summary,
                remoteSummary: remoteSummary,
                mergeDescription: mergeDescription(
                    localSummary: summary,
                    remoteSummary: remoteSummary
                )
            )
        } catch {
            update(
                phase: phase(for: await transport?.status()),
                errorMessage: userMessage(for: error)
            )
            throw error
        }
    }

    func enable() async throws {
        guard !snapshot.isEnabled else {
            throw CoordinatorError.alreadyEnabled
        }
        guard !isOperationRunning else {
            throw DatasetAccessError.maintenanceInProgress
        }
        isOperationRunning = true
        update(phase: .preparing, errorMessage: nil)
        defer { isOperationRunning = false }

        let dependencies = try requiredDependencies()
        do {
            try await dependencies.transport.checkAvailability()
            let package = try await dependencies.dataExchange.prepareExport()
            let summary = try await localSummary(
                dataExchange: dependencies.dataExchange,
                preparedPackage: package
            )
            let safetySnapshotURL = try await safetySnapshotService.write(
                package,
                datasetID: descriptor.datasetID
            )
            defaults.set(
                safetySnapshotURL.path,
                forKey: PreferenceKey.iCloudLastSafetySnapshotPath
            )
            update(
                phase: .preparing,
                localSummary: summary,
                lastSafetySnapshotURL: safetySnapshotURL
            )
            _ = try await dependencies.bootstrapStore
                .bootstrapExistingRecords()
            await configureRemoteChangeHandler(
                on: dependencies.transport
            )
            try await dependencies.transport.start(
                automaticallySync: true
            )
            try await persistDescriptor(
                storageKind: .iCloud,
                lastSuccessfulSyncAt: nil
            )
            defaults.set(true, forKey: PreferenceKey.iCloudSyncEnabled)
            update(isEnabled: true, phase: .syncing)
            isPrepared = true
            try await performSync(
                transport: dependencies.transport
            )
        } catch {
            if !snapshot.isEnabled {
                await dependencies.transport.stop()
            }
            update(
                phase: phase(
                    for: await dependencies.transport.status()
                ),
                errorMessage: userMessage(for: error)
            )
            throw error
        }
    }

    func syncNow() async {
        guard snapshot.isEnabled, !isOperationRunning else { return }
        guard let transport else {
            update(
                phase: .failed,
                errorMessage: CoordinatorError.unavailable.localizedDescription
            )
            return
        }
        isOperationRunning = true
        defer { isOperationRunning = false }
        do {
            try await performSync(transport: transport)
        } catch {
            update(
                phase: phase(for: await transport.status()),
                errorMessage: userMessage(for: error)
            )
            await refreshQueue()
        }
    }

    func applicationDidBecomeActive() async {
        guard snapshot.isEnabled else { return }
        if !isPrepared {
            await prepareIfEnabled()
        } else {
            await syncNow()
        }
    }

    func localDataDidChange() async {
        guard snapshot.isEnabled, let bootstrapStore else { return }
        do {
            _ = try await bootstrapStore.bootstrapAssetRecords()
            try await transport?.notifyLocalChanges()
            await refreshQueue()
        } catch {
            update(errorMessage: userMessage(for: error))
        }
    }

    func disableKeepingLocalData() async throws {
        guard snapshot.isEnabled else {
            throw CoordinatorError.notEnabled
        }
        guard !isOperationRunning else {
            throw DatasetAccessError.maintenanceInProgress
        }
        isOperationRunning = true
        defer { isOperationRunning = false }
        await transport?.stop()
        await transport?.setRemoteChangeHandler(nil)
        do {
            try await persistDescriptor(
                storageKind: .local,
                lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt
            )
            defaults.set(false, forKey: PreferenceKey.iCloudSyncEnabled)
            isPrepared = false
            update(
                isEnabled: false,
                phase: .disabled,
                queue: .empty,
                errorMessage: nil
            )
        } catch {
            update(
                phase: .failed,
                errorMessage: userMessage(for: error)
            )
            throw error
        }
    }

    func refreshStatus() async {
        await refreshQueue()
        guard snapshot.isEnabled else { return }
        update(phase: phase(for: await transport?.status()))
    }

    func resolveConflict(
        _ conflictID: UUID,
        resolution: CloudSyncConflictResolution
    ) async throws {
        guard snapshot.isEnabled else {
            throw CoordinatorError.notEnabled
        }
        guard !isOperationRunning else {
            throw DatasetAccessError.maintenanceInProgress
        }
        guard let remoteChangeApplier else {
            throw CoordinatorError.unavailable
        }
        isOperationRunning = true
        defer { isOperationRunning = false }
        do {
            try await remoteChangeApplier.resolveConflict(
                conflictID,
                resolution: resolution
            )
            if resolution == .keepLocal {
                try await transport?.notifyLocalChanges()
            }
            dataChangeHandler?()
            await refreshQueue()
            update(
                phase: snapshot.queue.conflictCount > 0
                    ? .conflicted
                    : .idle,
                errorMessage: nil
            )
        } catch {
            update(errorMessage: userMessage(for: error))
            await refreshQueue()
            throw error
        }
    }

    func setDataChangeHandler(_ handler: @escaping () -> Void) {
        dataChangeHandler = handler
    }

    private func performSync(
        transport: any CloudSyncTransport
    ) async throws {
        update(phase: .syncing, errorMessage: nil)
        try await transport.syncNow()
        await refreshQueue()
        let transportStatus = await transport.status()
        guard transportStatus == .idle,
              snapshot.queue.pendingDownloadCount == 0 else {
            update(phase: phase(for: transportStatus))
            return
        }
        let now = Date()
        defaults.set(
            now,
            forKey: PreferenceKey.iCloudLastSuccessfulSyncAt
        )
        try await persistDescriptor(
            storageKind: .iCloud,
            lastSuccessfulSyncAt: now
        )
        update(
            phase: snapshot.queue.conflictCount > 0
                ? .conflicted
                : .idle,
            lastSuccessfulSyncAt: now,
            errorMessage: nil
        )
        dataChangeHandler?()
    }

    private func refreshQueue() async {
        guard let statusStore else { return }
        do {
            async let queue = statusStore.snapshot()
            async let conflicts = statusStore.unresolvedConflicts()
            update(
                queue: try await queue,
                conflicts: try await conflicts
            )
        } catch {
            update(errorMessage: userMessage(for: error))
        }
    }

    private func localSummary(
        dataExchange: DataExchangeService,
        preparedPackage: EncodedDataPackage? = nil,
        includesPreparedPackage: Bool = true
    ) async throws -> CloudSyncDataSummary {
        let preview = try await dataExchange.previewExport()
        let assetFiles: [String: Data]
        if let preparedPackage {
            assetFiles = preparedPackage.files.filter {
                $0.key.hasPrefix("assets/")
            }
        } else if includesPreparedPackage {
            assetFiles = try await dataExchange.prepareExport().files.filter {
                $0.key.hasPrefix("assets/")
            }
        } else {
            let assets = try await dataExchange.previewAssets()
            return CloudSyncDataSummary(
                subscriptions: preview.subscriptions,
                periods: preview.periods,
                payments: preview.payments,
                templates: preview.templates,
                categories: preview.categories,
                assignments: preview.assignments,
                imageCount: assets.assetCount,
                estimatedBytes: assets.estimatedBytes
            )
        }
        return CloudSyncDataSummary(
            subscriptions: preview.subscriptions,
            periods: preview.periods,
            payments: preview.payments,
            templates: preview.templates,
            categories: preview.categories,
            assignments: preview.assignments,
            imageCount: assetFiles.count,
            estimatedBytes: assetFiles.values.reduce(0) {
                $0 + Int64($1.count)
            }
        )
    }

    private func mergeDescription(
        localSummary: CloudSyncDataSummary,
        remoteSummary: CloudSyncDataSummary
    ) -> String {
        if remoteSummary.isEmpty {
            return AppLocalization.string("iCloud 中没有现有 Periodic 数据。启用后会上传此 Mac 的记录。")
        }
        if localSummary.isEmpty {
            return AppLocalization.string("此 Mac 没有现有订阅数据。启用后会下载 iCloud 中的记录。")
        }
        return AppLocalization.string("Periodic 会按稳定 ID 合并此 Mac 与 iCloud 中的数据；名称相同不会被当作同一条记录。")
    }

    private func requiredDependencies() throws -> Dependencies {
        guard let transport,
              let bootstrapStore,
              let dataExchange else {
            throw CoordinatorError.unavailable
        }
        return Dependencies(
            transport: transport,
            bootstrapStore: bootstrapStore,
            dataExchange: dataExchange
        )
    }

    private func persistDescriptor(
        storageKind: DatasetStorageKind,
        lastSuccessfulSyncAt: Date?
    ) async throws {
        let previous = descriptor
        let updated = DatasetDescriptor(
            datasetID: descriptor.datasetID,
            storageKind: storageKind,
            schemaVersion: DatasetDescriptor.currentSchemaVersion,
            cloudZoneName: storageKind == .iCloud
                ? AppConfiguration.defaultCloudZoneName
                : nil,
            createdAt: descriptor.createdAt,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt
        )
        do {
            try descriptorRepository?.save(updated)
            try await metadataStore?.apply(updated)
            descriptor = updated
        } catch {
            try? descriptorRepository?.save(previous)
            try? await metadataStore?.apply(previous)
            throw error
        }
    }

    private func phase(
        for status: CloudSyncTransportStatus?
    ) -> CloudSyncPhase {
        guard let status else { return .failed }
        switch status {
        case .stopped:
            return snapshot.isEnabled ? .checking : .disabled
        case .idle:
            return snapshot.queue.conflictCount > 0 ? .conflicted : .idle
        case .syncing:
            return .syncing
        case .retrying:
            return .retrying
        case .needsAccount:
            return .needsAccount
        case .accountChanged:
            return .accountChanged
        case .failed:
            return .failed
        }
    }

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private func configureRemoteChangeHandler(
        on transport: any CloudSyncTransport
    ) async {
        await transport.setRemoteChangeHandler { [weak self] in
            Task { @MainActor in
                self?.handleRemoteChangesApplied()
            }
        }
    }

    private func handleRemoteChangesApplied() {
        dataChangeHandler?()
        Task {
            await refreshQueue()
        }
    }

    private func update(
        isEnabled: Bool? = nil,
        phase: CloudSyncPhase? = nil,
        localSummary: CloudSyncDataSummary? = nil,
        queue: CloudSyncQueueSnapshot? = nil,
        conflicts: [CloudSyncConflictSummary]? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        lastSafetySnapshotURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        snapshot = CloudSyncPresentationSnapshot(
            isEnabled: isEnabled ?? snapshot.isEnabled,
            phase: phase ?? snapshot.phase,
            localSummary: localSummary ?? snapshot.localSummary,
            queue: queue ?? snapshot.queue,
            conflicts: conflicts ?? snapshot.conflicts,
            lastSuccessfulSyncAt:
                lastSuccessfulSyncAt ?? snapshot.lastSuccessfulSyncAt,
            lastSafetySnapshotURL:
                lastSafetySnapshotURL ?? snapshot.lastSafetySnapshotURL,
            errorMessage: errorMessage
        )
    }

    private struct Dependencies {
        let transport: any CloudSyncTransport
        let bootstrapStore: SyncBootstrapStore
        let dataExchange: DataExchangeService
    }
}
