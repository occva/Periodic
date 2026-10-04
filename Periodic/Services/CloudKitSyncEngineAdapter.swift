import CloudKit
import CryptoKit
import Foundation

actor CloudKitSyncEngineAdapter: CKSyncEngineDelegate {
    enum AdapterError: LocalizedError, Equatable {
        case notStarted
        case accountUnavailable
        case accountRestricted
        case accountTemporarilyUnavailable
        case accountStatusUnknown
        case accountChanged
        case syncIncomplete
        case remoteHardDeletion
        case zoneDeleted

        var errorDescription: String? {
            switch self {
            case .notStarted:
                AppLocalization.string("iCloud 同步尚未启动。")
            case .accountUnavailable:
                AppLocalization.string("未登录可用的 iCloud 账号。")
            case .accountRestricted:
                AppLocalization.string("当前设备限制了 iCloud 访问。")
            case .accountTemporarilyUnavailable:
                AppLocalization.string("iCloud 暂时不可用，请稍后重试。")
            case .accountStatusUnknown:
                AppLocalization.string("无法确认 iCloud 账号状态。")
            case .accountChanged:
                AppLocalization.string("当前 Apple ID 与此数据集之前使用的账号不同。为避免混合数据，同步已暂停。")
            case .syncIncomplete:
                AppLocalization.string("iCloud 尚未完成本次同步，请稍后重试。")
            case .remoteHardDeletion:
                AppLocalization.string("云端出现了无法按墓碑规则处理的直接删除。")
            case .zoneDeleted:
                AppLocalization.string("Periodic 的 iCloud 同步区域已被删除。")
            }
        }
    }

    private let containerIdentifier: String
    private let zoneID: CKRecordZone.ID
    private let subscriptionID: CKSubscription.ID
    private let stateRepository: CloudSyncEngineStateRepository
    private let accountIdentityRepository: CloudAccountIdentityRepository
    private let datasetAccess: DatasetAccessCoordinator
    private let mutationStore: SyncMutationStore
    private let snapshotStore: SyncRecordSnapshotStore
    private let inboxStore: SyncRemoteInboxStore
    private let remoteChangeApplier: SyncRemoteChangeApplier
    private let assetRepository: CloudAssetRepository
    private var syncEngine: CKSyncEngine?
    private var transportStatus: CloudSyncTransportStatus = .stopped
    private var canPersistState = true
    private var isBlocked = false
    private var inFlightUploads: [CKRecord.ID: InFlightUpload] = [:]
    private var remoteChangeHandler: (@Sendable () -> Void)?

    init(
        containerIdentifier: String,
        zoneName: String,
        stateRepository: CloudSyncEngineStateRepository,
        accountIdentityRepository: CloudAccountIdentityRepository,
        datasetAccess: DatasetAccessCoordinator,
        mutationStore: SyncMutationStore,
        snapshotStore: SyncRecordSnapshotStore,
        inboxStore: SyncRemoteInboxStore,
        remoteChangeApplier: SyncRemoteChangeApplier,
        assetRepository: CloudAssetRepository
    ) {
        self.containerIdentifier = containerIdentifier
        zoneID = CKRecordZone.ID(zoneName: zoneName)
        subscriptionID = "Periodic." + zoneName
        self.stateRepository = stateRepository
        self.accountIdentityRepository = accountIdentityRepository
        self.datasetAccess = datasetAccess
        self.mutationStore = mutationStore
        self.snapshotStore = snapshotStore
        self.inboxStore = inboxStore
        self.remoteChangeApplier = remoteChangeApplier
        self.assetRepository = assetRepository
    }

    func status() async -> CloudSyncTransportStatus {
        transportStatus
    }

    func checkAvailability() async throws {
        let container = CKContainer(identifier: containerIdentifier)
        do {
            let fingerprint = try await accountFingerprint(container)
            try validateAccountIdentity(
                fingerprint,
                bindsIfMissing: false
            )
            if syncEngine == nil {
                transportStatus = .stopped
            }
        } catch let error as AdapterError {
            throw error
        } catch {
            handleOperationError(error)
            throw error
        }
    }

    func previewRemoteInventory() async throws -> CloudRecordInventory {
        let container = CKContainer(identifier: containerIdentifier)
        do {
            let fingerprint = try await accountFingerprint(container)
            try validateAccountIdentity(
                fingerprint,
                bindsIfMissing: false
            )
            let database = container.privateCloudDatabase
            do {
                _ = try await database.recordZone(for: zoneID)
            } catch {
                if isMissingRemoteObject(error) {
                    return .empty
                }
                throw error
            }

            var recordCounts: [SyncRecordType: Int] = [:]
            var estimatedAssetBytes: Int64 = 0
            for recordType in SyncRecordType.allCases {
                do {
                    let entries = try await inventoryEntries(
                        recordType: recordType,
                        database: database
                    )
                    for entry in entries where !entry.isDeleted {
                        recordCounts[entry.recordType, default: 0] += 1
                        let (nextBytes, overflow) =
                            estimatedAssetBytes.addingReportingOverflow(
                                Int64(entry.assetByteCount)
                            )
                        guard !overflow else {
                            throw CloudRecordCodec.CodecError.invalidPayload
                        }
                        estimatedAssetBytes = nextBytes
                    }
                } catch {
                    if isMissingRemoteObject(error) {
                        continue
                    }
                    throw error
                }
            }
            return CloudRecordInventory(
                recordCounts: recordCounts,
                estimatedAssetBytes: estimatedAssetBytes
            )
        } catch let error as AdapterError {
            throw error
        } catch {
            handleOperationError(error)
            throw error
        }
    }

    func start(automaticallySync: Bool = true) async throws {
        guard syncEngine == nil else { return }
        let container = CKContainer(identifier: containerIdentifier)
        do {
            let fingerprint = try await accountFingerprint(container)
            try validateAccountIdentity(
                fingerprint,
                bindsIfMissing: true
            )
        } catch let error as AdapterError {
            throw error
        } catch {
            handleOperationError(error)
            throw error
        }
        let stateSerialization: CKSyncEngine.State.Serialization?
        do {
            stateSerialization = try stateRepository.load()
        } catch {
            transportStatus = .failed(.statePersistence)
            throw error
        }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: stateSerialization,
            delegate: self
        )
        configuration.automaticallySync = automaticallySync
        configuration.subscriptionID = subscriptionID
        let engine = CKSyncEngine(configuration)
        syncEngine = engine
        canPersistState = true
        isBlocked = false
        transportStatus = .idle
        engine.state.add(
            pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: zoneID)),
            ]
        )
        do {
            try await queuePendingLocalChanges(on: engine)
            await datasetAccess.setWriteReleaseHandler { [weak self] in
                Task {
                    await self?.handleDatasetWriteRelease()
                }
            }
        } catch {
            self.syncEngine = nil
            transportStatus = .failed(.localPersistence)
            throw error
        }
    }

    func stop() async {
        guard let syncEngine else {
            transportStatus = .stopped
            return
        }
        await syncEngine.cancelOperations()
        self.syncEngine = nil
        await releaseInFlightAssets()
        inFlightUploads.removeAll()
        await datasetAccess.setWriteReleaseHandler(nil)
        transportStatus = .stopped
    }

    func setRemoteChangeHandler(
        _ handler: (@Sendable () -> Void)?
    ) async {
        remoteChangeHandler = handler
    }

    func notifyLocalChanges() async throws {
        guard let syncEngine else {
            throw AdapterError.notStarted
        }
        guard !isBlocked else { return }
        try await queuePendingLocalChanges(on: syncEngine)
    }

    func syncNow() async throws {
        guard let syncEngine else {
            throw AdapterError.notStarted
        }
        guard !isBlocked else {
            throw AdapterError.accountUnavailable
        }
        transportStatus = .syncing
        do {
            try await syncEngine.fetchChanges(
                CKSyncEngine.FetchChangesOptions(
                    scope: .zoneIDs([zoneID])
                )
            )
            _ = try await remoteChangeApplier.applyPending()
            try await queuePendingLocalChanges(on: syncEngine)
            try await syncEngine.sendChanges(
                CKSyncEngine.SendChangesOptions(
                    scope: .zoneIDs([zoneID])
                )
            )
            if isBlocked {
                throw AdapterError.accountUnavailable
            }
            guard transportStatus == .syncing
                    || transportStatus == .idle else {
                throw AdapterError.syncIncomplete
            }
            transportStatus = .idle
        } catch {
            handleOperationError(error)
            throw error
        }
    }

    func handleEvent(
        _ event: CKSyncEngine.Event,
        syncEngine: CKSyncEngine
    ) async {
        guard self.syncEngine === syncEngine else { return }
        switch event {
        case .stateUpdate(let update):
            guard canPersistState else { return }
            do {
                try stateRepository.save(update.stateSerialization)
            } catch {
                transportStatus = .failed(.statePersistence)
                AppLog.cloudSync.error(
                    "Failed to persist CKSyncEngine state"
                )
            }
        case .accountChange(let change):
            await handleAccountChange(change, syncEngine: syncEngine)
        case .fetchedDatabaseChanges(let changes):
            await handleFetchedDatabaseChanges(
                changes,
                syncEngine: syncEngine
            )
        case .fetchedRecordZoneChanges(let changes):
            await handleFetchedRecordZoneChanges(
                changes,
                syncEngine: syncEngine
            )
        case .sentDatabaseChanges(let changes):
            handleSentDatabaseChanges(changes)
        case .sentRecordZoneChanges(let changes):
            await handleSentRecordZoneChanges(
                changes,
                syncEngine: syncEngine
            )
        case .willFetchChanges,
             .willFetchRecordZoneChanges,
             .willSendChanges:
            if !isBlocked {
                transportStatus = .syncing
            }
        case .didFetchRecordZoneChanges(let result):
            if let error = result.error {
                handleCloudKitError(error)
            }
        case .didFetchChanges,
             .didSendChanges:
            if !isBlocked, transportStatus == .syncing {
                transportStatus = .idle
            }
        @unknown default:
            await blockCurrentEngine(
                syncEngine,
                status: .failed(.cloudKit(code: -1))
            )
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard self.syncEngine === syncEngine, !isBlocked else {
            return nil
        }
        var newlyStagedAssets: [CloudAssetRepository.UploadAsset] = []
        do {
            let pendingMutations = try await mutationStore.fetchPending(
                limit: 5_000
            )
            let snapshots = try await snapshotStore.snapshots(
                for: pendingMutations
            )
            let uploads = try SyncUploadBatchBuilder.build(
                mutations: pendingMutations,
                snapshots: snapshots
            )
            let uploadsByRecordID = Dictionary(
                uniqueKeysWithValues: uploads.map {
                    (
                        CloudRecordCodec.cloudRecordID(
                            recordType: $0.snapshot.recordType,
                            recordID: $0.snapshot.recordID,
                            zoneID: zoneID
                        ),
                        $0
                    )
                }
            )
            let pendingChanges = syncEngine.state.pendingRecordZoneChanges
                .filter { context.options.scope.contains($0) }
            var recordsToSave: [CKRecord] = []
            var staleChanges: [CKSyncEngine.PendingRecordZoneChange] = []
            for pendingChange in pendingChanges.prefix(200) {
                switch pendingChange {
                case .saveRecord(let recordID):
                    guard let upload = uploadsByRecordID[recordID] else {
                        staleChanges.append(pendingChange)
                        continue
                    }
                    let asset: CloudAssetRepository.UploadAsset?
                    if upload.snapshot.recordType == .iconAsset,
                       !upload.snapshot.isDeleted {
                        asset = try await assetRepository.stageUpload(
                            reference: upload.snapshot.recordID
                        )
                        if let asset {
                            newlyStagedAssets.append(asset)
                        }
                    } else {
                        asset = nil
                    }
                    recordsToSave.append(
                        try CloudRecordCodec.makeRecord(
                            upload: upload,
                            zoneID: zoneID,
                            assetFileURL: asset?.stagedImage.fileURL,
                            assetMetadata: asset.map {
                                CloudAssetMetadata(
                                    contentHash:
                                        $0.stagedImage.contentHash,
                                    format: $0.stagedImage.format,
                                    byteCount: $0.stagedImage.byteCount
                                )
                            }
                        )
                    )
                    inFlightUploads[recordID] = InFlightUpload(
                        upload: upload,
                        asset: asset
                    )
                case .deleteRecord:
                    staleChanges.append(pendingChange)
                @unknown default:
                    transportStatus = .failed(.cloudKit(code: -1))
                    return nil
                }
            }
            if !staleChanges.isEmpty {
                syncEngine.state.remove(
                    pendingRecordZoneChanges: staleChanges
                )
            }
            guard !recordsToSave.isEmpty else { return nil }
            return CKSyncEngine.RecordZoneChangeBatch(
                recordsToSave: recordsToSave,
                atomicByZone: false
            )
        } catch {
            await assetRepository.release(newlyStagedAssets)
            for recordID in inFlightUploads.compactMap({ key, value in
                newlyStagedAssets.contains(where: {
                    $0.stagedImage.leaseID
                        == value.asset?.stagedImage.leaseID
                }) ? key : nil
            }) {
                inFlightUploads.removeValue(forKey: recordID)
            }
            transportStatus = .failed(.localPersistence)
            AppLog.cloudSync.error(
                "Failed to build CKSyncEngine upload batch"
            )
            return nil
        }
    }

    private func accountFingerprint(
        _ container: CKContainer
    ) async throws -> String {
        switch try await container.accountStatus() {
        case .available:
            let recordID = try await container.userRecordID()
            return SHA256.hash(
                data: Data(
                    (containerIdentifier + ":" + recordID.recordName).utf8
                )
            )
            .map { String(format: "%02x", $0) }
            .joined()
        case .noAccount:
            transportStatus = .needsAccount
            throw AdapterError.accountUnavailable
        case .restricted:
            transportStatus = .needsAccount
            throw AdapterError.accountRestricted
        case .temporarilyUnavailable:
            transportStatus = .retrying
            throw AdapterError.accountTemporarilyUnavailable
        case .couldNotDetermine:
            transportStatus = .failed(.cloudKit(code: -1))
            throw AdapterError.accountStatusUnknown
        @unknown default:
            transportStatus = .failed(.cloudKit(code: -1))
            throw AdapterError.accountStatusUnknown
        }
    }

    private func validateAccountIdentity(
        _ fingerprint: String,
        bindsIfMissing: Bool
    ) throws {
        if let existing = try accountIdentityRepository.load() {
            guard existing == fingerprint else {
                transportStatus = .accountChanged
                isBlocked = true
                throw AdapterError.accountChanged
            }
            return
        }
        guard bindsIfMissing else { return }
        do {
            try accountIdentityRepository.save(fingerprint)
        } catch {
            transportStatus = .failed(.statePersistence)
            throw error
        }
    }

    private func inventoryEntries(
        recordType: SyncRecordType,
        database: CKDatabase
    ) async throws -> [CloudRecordCodec.InventoryEntry] {
        let query = CKQuery(
            recordType: CloudRecordCodec.cloudRecordType(recordType),
            predicate: NSPredicate(value: true)
        )
        var response = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: CloudRecordCodec.inventoryDesiredKeys
        )
        var entries: [CloudRecordCodec.InventoryEntry] = []
        while true {
            for (_, result) in response.matchResults {
                entries.append(
                    try CloudRecordCodec.decodeInventoryEntry(
                        result.get()
                    )
                )
            }
            guard let cursor = response.queryCursor else {
                return entries
            }
            response = try await database.records(
                continuingMatchFrom: cursor,
                desiredKeys: CloudRecordCodec.inventoryDesiredKeys
            )
        }
    }

    private func isMissingRemoteObject(_ error: any Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        return cloudError.code == .unknownItem
            || cloudError.code == .zoneNotFound
    }

    private func queuePendingLocalChanges(
        on syncEngine: CKSyncEngine
    ) async throws {
        let pending = try await mutationStore.fetchPending(limit: 5_000)
        let existing = Set(syncEngine.state.pendingRecordZoneChanges)
        let changes = Set(pending.map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(
                CloudRecordCodec.cloudRecordID(
                    recordType: $0.recordType,
                    recordID: $0.recordID,
                    zoneID: zoneID
                )
            )
        }).subtracting(existing)
        if !changes.isEmpty {
            syncEngine.state.add(
                pendingRecordZoneChanges: Array(changes)
            )
        }
    }

    private func handleFetchedRecordZoneChanges(
        _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        do {
            let targetDeletions = changes.deletions.filter {
                $0.recordID.zoneID == zoneID
            }
            guard targetDeletions.isEmpty else {
                throw AdapterError.remoteHardDeletion
            }
            var remoteChanges: [SyncRemoteChange] = []
            var stagedDownloads: [String: StagedRemoteAsset] = [:]
            var didEnqueueChanges = false
            defer {
                if !didEnqueueChanges, !stagedDownloads.isEmpty {
                    let assets = stagedDownloads.values.map(\.asset)
                    Task {
                        await assetRepository.release(assets)
                    }
                }
            }
            for modification in changes.modifications {
                let record = modification.record
                guard record.recordID.zoneID == zoneID else {
                    continue
                }
                let envelope = try CloudRecordCodec.decode(record)
                let systemFields = CloudRecordCodec.systemFieldsData(
                    for: record
                )
                let changeID = sourceChangeID(
                    for: record,
                    systemFields: systemFields
                )
                if envelope.recordType == .iconAsset,
                   !envelope.isDeleted {
                    let payload = try SyncRecordPayloadDecoder.iconAsset(
                        recordID: envelope.recordID,
                        fieldValues: envelope.fieldValues
                    )
                    stagedDownloads[changeID] = StagedRemoteAsset(
                        envelope: envelope,
                        asset: try await assetRepository.stageDownload(
                            reference: payload.reference,
                            fileURL: try CloudRecordCodec.assetFileURL(
                                for: record
                            ),
                            metadata: payload.metadata
                        )
                    )
                }
                remoteChanges.append(
                    SyncRemoteChange(
                        sourceChangeID: changeID,
                        envelope: envelope,
                        serverRecordData: systemFields,
                        receivedAt: .now
                    ),
                )
            }
            _ = try await inboxStore.enqueue(remoteChanges)
            didEnqueueChanges = true
            canPersistState = true
            let report = try await remoteChangeApplier.applyPending()
            try await releaseFinishedStagedAssets(
                stagedDownloads: &stagedDownloads
            )
            try await queuePendingLocalChanges(on: syncEngine)
            if report.appliedCount > 0 {
                remoteChangeHandler?()
            }
        } catch {
            let failure: CloudSyncTransportFailure =
                error as? AdapterError == .remoteHardDeletion
                    ? .remoteHardDeletion
                    : .invalidRemoteData
            await blockCurrentEngine(
                syncEngine,
                status: .failed(failure)
            )
            AppLog.cloudSync.error(
                "Failed to persist fetched CloudKit records"
            )
        }
    }

    private func handleFetchedDatabaseChanges(
        _ changes: CKSyncEngine.Event.FetchedDatabaseChanges,
        syncEngine: CKSyncEngine
    ) async {
        guard changes.deletions.contains(where: {
            $0.zoneID == zoneID
        }) else {
            return
        }
        await blockCurrentEngine(
            syncEngine,
            status: .failed(.zoneDeleted)
        )
    }

    private func handleSentDatabaseChanges(
        _ changes: CKSyncEngine.Event.SentDatabaseChanges
    ) {
        guard let error = changes.failedZoneSaves.first(
            where: { $0.zone.zoneID == zoneID }
        )?.error else {
            return
        }
        handleCloudKitError(error)
    }

    private func handleSentRecordZoneChanges(
        _ changes: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        for record in changes.savedRecords where
            record.recordID.zoneID == zoneID {
            guard let inFlight = inFlightUploads.removeValue(
                forKey: record.recordID
            ) else {
                continue
            }
            defer {
                if let asset = inFlight.asset {
                    Task {
                        await assetRepository.release([asset])
                    }
                }
            }
            do {
                try await mutationStore.acknowledgeUpload(
                    mutationIDs: Set(inFlight.upload.mutationIDs),
                    recordType: inFlight.upload.snapshot.recordType,
                    recordID: inFlight.upload.snapshot.recordID,
                    serverRecordData: CloudRecordCodec.systemFieldsData(
                        for: record
                    )
                )
            } catch {
                transportStatus = .failed(.localPersistence)
                AppLog.cloudSync.error(
                    "Failed to acknowledge uploaded CloudKit record"
                )
            }
        }

        for failure in changes.failedRecordSaves where
            failure.record.recordID.zoneID == zoneID {
            let inFlight = inFlightUploads.removeValue(
                forKey: failure.record.recordID
            )
            if let asset = inFlight?.asset {
                await assetRepository.release([asset])
            }
            await handleFailedRecordSave(
                failure,
                upload: inFlight?.upload,
                syncEngine: syncEngine
            )
        }

        do {
            try await queuePendingLocalChanges(on: syncEngine)
        } catch {
            transportStatus = .failed(.localPersistence)
        }
    }

    private func handleFailedRecordSave(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        upload: SyncUploadRecord?,
        syncEngine: CKSyncEngine
    ) async {
        let error = failure.error
        switch error.code {
        case .serverRecordChanged:
            guard let serverRecord = error.serverRecord else {
                transportStatus = .failed(
                    .cloudKit(code: error.code.rawValue)
                )
                return
            }
            do {
                let envelope = try CloudRecordCodec.decode(serverRecord)
                let systemFields = CloudRecordCodec.systemFieldsData(
                    for: serverRecord
                )
                let changeID = sourceChangeID(
                    for: serverRecord,
                    systemFields: systemFields
                )
                var stagedDownload: StagedRemoteAsset?
                if envelope.recordType == .iconAsset,
                   !envelope.isDeleted {
                    let payload = try SyncRecordPayloadDecoder.iconAsset(
                        recordID: envelope.recordID,
                        fieldValues: envelope.fieldValues
                    )
                    stagedDownload = StagedRemoteAsset(
                        envelope: envelope,
                        asset: try await assetRepository.stageDownload(
                            reference: payload.reference,
                            fileURL: try CloudRecordCodec.assetFileURL(
                                for: serverRecord
                            ),
                            metadata: payload.metadata
                        )
                    )
                }
                _ = try await inboxStore.enqueue([
                    SyncRemoteChange(
                        sourceChangeID: changeID,
                        envelope: envelope,
                        serverRecordData: systemFields,
                        receivedAt: .now
                    ),
                ])
                let report = try await remoteChangeApplier.applyPending()
                if let stagedDownload {
                    var stagedDownloads = [changeID: stagedDownload]
                    try await releaseFinishedStagedAssets(
                        stagedDownloads: &stagedDownloads
                    )
                }
                try await queuePendingLocalChanges(on: syncEngine)
                if report.appliedCount > 0 {
                    remoteChangeHandler?()
                }
            } catch {
                transportStatus = .failed(.invalidRemoteData)
            }
        case .zoneNotFound:
            guard upload?.snapshot.serverRecordData == nil else {
                await blockCurrentEngine(
                    syncEngine,
                    status: .failed(.zoneDeleted)
                )
                return
            }
            syncEngine.state.add(
                pendingDatabaseChanges: [
                    .saveZone(CKRecordZone(zoneID: zoneID)),
                ]
            )
            syncEngine.state.add(
                pendingRecordZoneChanges: [
                    .saveRecord(failure.record.recordID),
                ]
            )
        case .unknownItem:
            guard upload?.snapshot.serverRecordData == nil else {
                await blockCurrentEngine(
                    syncEngine,
                    status: .failed(.remoteHardDeletion)
                )
                return
            }
            syncEngine.state.add(
                pendingRecordZoneChanges: [
                    .saveRecord(failure.record.recordID),
                ]
            )
        default:
            handleCloudKitError(error)
        }
    }

    private func handleAccountChange(
        _ change: CKSyncEngine.Event.AccountChange,
        syncEngine: CKSyncEngine
    ) async {
        switch change.changeType {
        case .signIn:
            if !isBlocked {
                transportStatus = .idle
            }
        case .signOut:
            await blockCurrentEngine(
                syncEngine,
                status: .needsAccount
            )
        case .switchAccounts:
            await blockCurrentEngine(
                syncEngine,
                status: .accountChanged
            )
        @unknown default:
            await blockCurrentEngine(
                syncEngine,
                status: .failed(.cloudKit(code: -1))
            )
        }
    }

    private func blockCurrentEngine(
        _ syncEngine: CKSyncEngine,
        status: CloudSyncTransportStatus
    ) async {
        guard self.syncEngine === syncEngine else { return }
        canPersistState = false
        isBlocked = true
        transportStatus = status
        await syncEngine.cancelOperations()
        self.syncEngine = nil
        await releaseInFlightAssets()
        inFlightUploads.removeAll()
        await datasetAccess.setWriteReleaseHandler(nil)
    }

    private func handleOperationError(_ error: any Error) {
        if let cloudError = error as? CKError {
            handleCloudKitError(cloudError)
        } else if error is AdapterError {
            return
        } else {
            transportStatus = .failed(.localPersistence)
        }
    }

    private func handleDatasetWriteRelease() async {
        guard let syncEngine, !isBlocked else { return }
        do {
            try await queuePendingLocalChanges(on: syncEngine)
        } catch {
            transportStatus = .failed(.localPersistence)
        }
    }

    private func handleCloudKitError(_ error: CKError) {
        switch error.code {
        case .networkFailure,
             .networkUnavailable,
             .requestRateLimited,
             .serviceUnavailable,
             .zoneBusy:
            transportStatus = .retrying
        case .notAuthenticated:
            transportStatus = .needsAccount
            isBlocked = true
        default:
            transportStatus = .failed(
                .cloudKit(code: error.code.rawValue)
            )
        }
    }

    private func releaseFinishedStagedAssets(
        stagedDownloads: inout [
            String: StagedRemoteAsset
        ]
    ) async throws {
        for (sourceChangeID, staged) in stagedDownloads {
            switch try await inboxStore.state(
                sourceChangeID: sourceChangeID
            ) {
            case .applied, .failed:
                await assetRepository.release([staged.asset])
                stagedDownloads.removeValue(forKey: sourceChangeID)
            case .pending, .conflicted, nil:
                continue
            }
        }
    }

    private func sourceChangeID(
        for record: CKRecord,
        systemFields: Data
    ) -> String {
        let version = record.recordChangeTag
            ?? SHA256.hash(data: systemFields)
                .map { String(format: "%02x", $0) }
                .joined()
        return [
            record.recordID.zoneID.ownerName,
            record.recordID.zoneID.zoneName,
            record.recordID.recordName,
            version,
        ].joined(separator: "/")
    }

    private func releaseInFlightAssets() async {
        await assetRepository.release(
            inFlightUploads.values.compactMap(\.asset)
        )
    }

    private struct InFlightUpload {
        let upload: SyncUploadRecord
        let asset: CloudAssetRepository.UploadAsset?
    }

    private struct StagedRemoteAsset {
        let envelope: CloudRecordEnvelope
        let asset: CloudAssetRepository.DownloadAsset
    }
}
