import Foundation
import Observation
import SwiftData

/// App-wide dependencies. Window selection and presentation state stay in views.
@MainActor
@Observable
final class AppServices {
    let persistence: PersistenceController
    let datasetDescriptor: DatasetDescriptor
    let datasetAccess: DatasetAccessCoordinator
    let deviceIdentity: DeviceIdentity
    let subscriptionStore: SubscriptionStore?
    let templateStore: TemplateStore?
    let templateCategoryStore: TemplateCategoryStore?
    let syncMutationStore: SyncMutationStore?
    let syncRecordSnapshotStore: SyncRecordSnapshotStore?
    let syncBootstrapStore: SyncBootstrapStore?
    let syncRemoteInboxStore: SyncRemoteInboxStore?
    let syncRemoteChangeApplier: SyncRemoteChangeApplier?
    let cloudSyncStatusStore: CloudSyncStatusStore?
    let cloudSyncMetadataStore: CloudSyncMetadataStore?
    let cloudKitSyncEngineAdapter: CloudKitSyncEngineAdapter?
    let cloudSyncCoordinator: CloudSyncCoordinator
    let appleIconSearch: AppleIconSearchClient
    let appleIconCache: AppleIconCache
    let paymentAttachmentStore: PaymentAttachmentStore
    let cloudImageAssetStager: CloudImageAssetStager
    let cloudAssetRepository: CloudAssetRepository
    let exchangeRates: FrankfurterExchangeRateClient
    let subscriptionNotifications: SubscriptionNotificationService
    let dataExchange: DataExchangeService?
    let builtinTemplateCategoryStore: BuiltinTemplateCategoryStore?
    let builtinTemplates: BuiltinTemplateCatalog?
    let modelContainer: ModelContainer?
    private(set) var initializationError: PresentedError?
    private(set) var builtinTemplateError: PresentedError?
    private(set) var subscriptionDataVersion = 0
    private(set) var templateDataVersion = 0
    private var didPrepareDevelopmentData = false
    private let defaults: UserDefaults
    private let usesPersistentStore: Bool

    init(
        persistence: PersistenceController = PersistenceController(),
        inMemory: Bool? = nil,
        appleIconCache: AppleIconCache? = nil,
        paymentAttachmentStore: PaymentAttachmentStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        let processArguments = ProcessInfo.processInfo.arguments
        let useMemoryStore = inMemory ?? processArguments.contains("-store-in-memory")
        let enablesSampleNotifications = useMemoryStore
            && processArguments.contains("-enable-test-notifications")
        let descriptor: DatasetDescriptor
        let descriptorRepository: DatasetDescriptorRepository?
        let resolvedDeviceIdentity: DeviceIdentity
        let descriptorError: (any Error)?
        if useMemoryStore {
            descriptor = .local()
            descriptorRepository = nil
            resolvedDeviceIdentity = DeviceIdentity()
            descriptorError = nil
        } else {
            do {
                let repository = DatasetDescriptorRepository(
                    descriptorURL: AppConfiguration.datasetDescriptorURL
                )
                let loadedDescriptor = try repository.loadOrCreate(
                    seedDatasetID: AppPreferenceValues.datasetID(in: defaults)
                )
                let loadedDeviceIdentity = try DeviceIdentityRepository(
                    identityURL: AppConfiguration.deviceIdentityURL
                ).loadOrCreate()
                descriptor = loadedDescriptor
                descriptorRepository = repository
                resolvedDeviceIdentity = loadedDeviceIdentity
                descriptorError = nil
                defaults.set(
                    loadedDescriptor.datasetID.uuidString,
                    forKey: PreferenceKey.datasetID
                )
            } catch {
                descriptor = .local(
                    datasetID: AppPreferenceValues.datasetID(in: defaults)
                )
                descriptorRepository = nil
                resolvedDeviceIdentity = DeviceIdentity()
                descriptorError = error
            }
        }
        let resolvedDatasetAccess = DatasetAccessCoordinator(
            descriptor: descriptor,
            deviceID: resolvedDeviceIdentity.id
        )
        let resolvedAppleIconCache = appleIconCache ?? AppleIconCache(
            storageRoot: Self.defaultIconStorageRoot(useMemoryStore: useMemoryStore)
        )
        let resolvedPaymentAttachmentStore = paymentAttachmentStore ?? PaymentAttachmentStore(
            storageRoot: Self.defaultPaymentAttachmentStorageRoot(
                useMemoryStore: useMemoryStore
            )
        )
        let resolvedCloudAssetStagingRoot = useMemoryStore
            ? FileManager.default.temporaryDirectory
                .appending(path: "PeriodicTests", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
                .appending(path: "CloudAssetStaging", directoryHint: .isDirectory)
            : AppConfiguration.cloudAssetStagingRoot
        self.persistence = persistence
        datasetDescriptor = descriptor
        datasetAccess = resolvedDatasetAccess
        deviceIdentity = resolvedDeviceIdentity
        self.defaults = defaults
        usesPersistentStore = !useMemoryStore
        appleIconSearch = AppleIconSearchClient()
        self.appleIconCache = resolvedAppleIconCache
        self.paymentAttachmentStore = resolvedPaymentAttachmentStore
        let resolvedCloudImageAssetStager = CloudImageAssetStager(
            stagingRoot: resolvedCloudAssetStagingRoot
        )
        cloudImageAssetStager = resolvedCloudImageAssetStager
        cloudAssetRepository = CloudAssetRepository(
            iconCache: resolvedAppleIconCache,
            paymentAttachmentStore: resolvedPaymentAttachmentStore,
            stager: resolvedCloudImageAssetStager
        )
        exchangeRates = FrankfurterExchangeRateClient()
        subscriptionNotifications = SubscriptionNotificationService(
            isSystemIntegrationEnabled: !useMemoryStore || enablesSampleNotifications,
            defaults: defaults,
            submissionHistoryKey: useMemoryStore
                ? PreferenceKey.submittedSampleNotificationRequests
                : PreferenceKey.submittedNotificationRequests,
            namespace: useMemoryStore ? .sample : .production,
            obsoleteNamespaces: useMemoryStore ? [] : [.sample]
        )
        do {
            builtinTemplates = try BuiltinTemplateCatalog.load()
        } catch {
            builtinTemplates = nil
            builtinTemplateError = PresentedError(error, title: "无法读取内置模板")
        }
        do {
            if let descriptorError {
                throw descriptorError
            }
            let schema = Schema(versionedSchema: AppSchemaV9.self)
            let container = try persistence.makeContainer(
                schema: schema,
                migrationPlan: AppSchemaMigrationPlan.self,
                inMemory: useMemoryStore
            )
            _ = try DatasetMetadata.prepare(
                in: ModelContext(container),
                descriptor: descriptor
            )
            modelContainer = container
            subscriptionStore = SubscriptionStore(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess
            )
            templateStore = TemplateStore(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess
            )
            templateCategoryStore = TemplateCategoryStore(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess
            )
            let resolvedSyncMutationStore = SyncMutationStore(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess
            )
            syncMutationStore = resolvedSyncMutationStore
            let resolvedSyncRecordSnapshotStore = SyncRecordSnapshotStore(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess,
                assetRepository: cloudAssetRepository
            )
            syncRecordSnapshotStore = resolvedSyncRecordSnapshotStore
            syncBootstrapStore = SyncBootstrapStore(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess,
                assetRepository: cloudAssetRepository
            )
            let resolvedSyncRemoteInboxStore = SyncRemoteInboxStore(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess
            )
            syncRemoteInboxStore = resolvedSyncRemoteInboxStore
            let resolvedSyncRemoteChangeApplier = SyncRemoteChangeApplier(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess,
                assetRepository: cloudAssetRepository
            )
            syncRemoteChangeApplier = resolvedSyncRemoteChangeApplier
            cloudSyncStatusStore = CloudSyncStatusStore(
                modelContainer: container
            )
            cloudSyncMetadataStore = CloudSyncMetadataStore(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess
            )
            if let containerIdentifier =
                AppConfiguration.iCloudContainerIdentifier {
                cloudKitSyncEngineAdapter = CloudKitSyncEngineAdapter(
                    containerIdentifier: containerIdentifier,
                    zoneName: AppConfiguration.defaultCloudZoneName,
                    stateRepository: CloudSyncEngineStateRepository(
                        stateURL: AppConfiguration.cloudSyncStateURL(
                            datasetID: descriptor.datasetID
                        )
                    ),
                    accountIdentityRepository:
                        CloudAccountIdentityRepository(
                            identityURL: AppConfiguration
                                .cloudAccountIdentityURL(
                                    datasetID: descriptor.datasetID
                                )
                        ),
                    datasetAccess: resolvedDatasetAccess,
                    mutationStore: resolvedSyncMutationStore,
                    snapshotStore: resolvedSyncRecordSnapshotStore,
                    inboxStore: resolvedSyncRemoteInboxStore,
                    remoteChangeApplier: resolvedSyncRemoteChangeApplier,
                    assetRepository: cloudAssetRepository
                )
            } else {
                cloudKitSyncEngineAdapter = nil
            }
            builtinTemplateCategoryStore = BuiltinTemplateCategoryStore(
                modelContainer: container,
                datasetAccess: resolvedDatasetAccess
            )
            dataExchange = DataExchangeService(
                store: DataExchangeStore(
                    modelContainer: container,
                    datasetAccess: resolvedDatasetAccess
                ),
                iconCache: resolvedAppleIconCache,
                paymentAttachmentStore: resolvedPaymentAttachmentStore
            )
        } catch {
            modelContainer = nil
            subscriptionStore = nil
            templateStore = nil
            templateCategoryStore = nil
            syncMutationStore = nil
            syncRecordSnapshotStore = nil
            syncBootstrapStore = nil
            syncRemoteInboxStore = nil
            syncRemoteChangeApplier = nil
            cloudSyncStatusStore = nil
            cloudSyncMetadataStore = nil
            cloudKitSyncEngineAdapter = nil
            builtinTemplateCategoryStore = nil
            dataExchange = nil
            initializationError = PresentedError(error, title: "无法打开订阅数据")
        }
        let safetySnapshotRoot = useMemoryStore
            ? FileManager.default.temporaryDirectory
                .appending(path: "PeriodicTests", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
                .appending(
                    path: "iCloud Safety Snapshots",
                    directoryHint: .isDirectory
                )
            : AppConfiguration.cloudSafetySnapshotRoot
        cloudSyncCoordinator = CloudSyncCoordinator(
            transport: cloudKitSyncEngineAdapter,
            bootstrapStore: syncBootstrapStore,
            statusStore: cloudSyncStatusStore,
            remoteChangeApplier: syncRemoteChangeApplier,
            dataExchange: dataExchange,
            metadataStore: cloudSyncMetadataStore,
            descriptorRepository: descriptorRepository,
            safetySnapshotService: CloudSyncSafetySnapshotService(
                root: safetySnapshotRoot
            ),
            descriptor: descriptor,
            defaults: defaults
        )
        cloudSyncCoordinator.setDataChangeHandler { [weak self] in
            guard let self else { return }
            subscriptionDataVersion &+= 1
            templateDataVersion &+= 1
        }
    }

    func prepareDevelopmentDataIfRequested(referenceDate: LocalDate = .today) async throws {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-store-in-memory"),
              arguments.contains("-seed-test-data"),
              !didPrepareDevelopmentData,
              let subscriptionStore else {
            return
        }
        didPrepareDevelopmentData = true
        let existingItems = try await subscriptionStore.fetchAll()
        guard existingItems.isEmpty else { return }
        let subscriptions = DevelopmentSubscriptionDataset.make(
            referenceDate: referenceDate,
            templates: builtinTemplates?.templates ?? []
        )
        try await subscriptionStore.create(
            subscriptions,
            additionalPeriods: DevelopmentSubscriptionDataset.makeHistoricalPeriods(
                for: subscriptions
            )
        )
        #endif
    }

    func prepareStoredSubscriptionData() async throws {
        guard usesPersistentStore, let subscriptionStore else { return }
        let datasetID = AppPreferenceValues.datasetID(in: defaults)
        let backfillKey = PreferenceKey.lifetimePeriodBackfillCompleted(
            datasetID: datasetID
        )
        if !defaults.bool(forKey: backfillKey) {
            _ = try await subscriptionStore.backfillLifetimePeriods()
            defaults.set(true, forKey: backfillKey)
        }
        await retryPendingIconCleanup()
        await retryPendingPaymentAttachmentCleanup()
        await removeOrphanedPaymentAttachments()
    }

    func notifySubscriptionDataChanged() {
        subscriptionDataVersion &+= 1
        Task {
            await cloudSyncCoordinator.localDataDidChange()
        }
    }

    func notifyTemplateDataChanged() {
        templateDataVersion &+= 1
        Task {
            await cloudSyncCoordinator.localDataDidChange()
        }
    }

    func previewSubscriptionDeletion(
        targets: [SubscriptionMutationTarget]
    ) async throws -> SubscriptionDeletionPreview {
        guard let subscriptionStore else { throw AppServicesError.storeUnavailable }
        return try await subscriptionStore.previewDeletion(targets)
    }

    func deleteSubscriptions(
        _ preview: SubscriptionDeletionPreview
    ) async throws -> SubscriptionDeletionOutcome {
        guard let subscriptionStore else { throw AppServicesError.storeUnavailable }
        let result = try await subscriptionStore.delete(preview)
        let pendingIconCleanupCount: Int
        let pendingPaymentAttachmentCleanupCount: Int
        if usesPersistentStore {
            let queuedReferences = pendingIconCleanupReferences.union(
                result.unreferencedIconReferences
            )
            storePendingIconCleanupReferences(queuedReferences)
            await retryPendingIconCleanup()
            pendingIconCleanupCount = pendingIconCleanupReferences.count
            let queuedAttachmentReferences = pendingPaymentAttachmentCleanupReferences.union(
                result.unreferencedPaymentAttachmentReferences
            )
            storePendingPaymentAttachmentCleanupReferences(queuedAttachmentReferences)
            await retryPendingPaymentAttachmentCleanup()
            pendingPaymentAttachmentCleanupCount =
                pendingPaymentAttachmentCleanupReferences.count
        } else {
            pendingIconCleanupCount = await appleIconCache.removeStoredImages(
                references: result.unreferencedIconReferences
            ).count
            pendingPaymentAttachmentCleanupCount = await paymentAttachmentStore
                .removeStoredImages(
                    references: result.unreferencedPaymentAttachmentReferences
                ).count
        }
        notifySubscriptionDataChanged()
        return SubscriptionDeletionOutcome(
            pendingIconCleanupCount: pendingIconCleanupCount,
            pendingPaymentAttachmentCleanupCount: pendingPaymentAttachmentCleanupCount
        )
    }

    func addPayment(_ input: SubscriptionPaymentAddInput) async throws {
        guard let subscriptionStore else { throw AppServicesError.storeUnavailable }
        try await subscriptionStore.addPayment(input)
        notifySubscriptionDataChanged()
    }

    func updatePayment(_ input: SubscriptionPaymentUpdateInput) async throws {
        guard let subscriptionStore else { throw AppServicesError.storeUnavailable }
        try await subscriptionStore.updatePayment(input)
        await cleanPaymentAttachments(
            candidates: Set(input.original.attachmentReferences)
        )
        notifySubscriptionDataChanged()
    }

    func deletePayment(_ input: SubscriptionPaymentDeleteInput) async throws {
        guard let subscriptionStore else { throw AppServicesError.storeUnavailable }
        try await subscriptionStore.deletePayment(input)
        await cleanPaymentAttachments(
            candidates: Set(input.original.attachmentReferences)
        )
        notifySubscriptionDataChanged()
    }

    func discardUncommittedPaymentAttachments(
        _ writes: [PaymentAttachmentStore.ImportedImageWrite],
        keeping additionalReferences: Set<String> = []
    ) async {
        guard let subscriptionStore else {
            await paymentAttachmentStore.releaseImportedImages(writes)
            return
        }
        do {
            let referenced = try await subscriptionStore
                .referencedPaymentAttachmentReferences()
            await paymentAttachmentStore.discardImportedImages(
                writes,
                keeping: referenced.union(additionalReferences)
            )
        } catch {
            // Retain the file if current database references cannot be read.
            await paymentAttachmentStore.releaseImportedImages(writes)
            AppLog.persistence.error("Failed to verify an uncommitted payment attachment")
        }
    }

    func finalizeCommittedPaymentAttachments(
        _ writes: [PaymentAttachmentStore.ImportedImageWrite],
        retainedReferences: Set<String>
    ) async {
        let retainedWrites = writes.filter { retainedReferences.contains($0.reference) }
        let discardedWrites = writes.filter { !retainedReferences.contains($0.reference) }
        await paymentAttachmentStore.releaseImportedImages(retainedWrites)
        await discardUncommittedPaymentAttachments(
            discardedWrites,
            keeping: retainedReferences
        )
    }

    func setSubscriptionManagementState(
        _ state: ManagementState,
        targets: [SubscriptionMutationTarget]
    ) async throws {
        guard let subscriptionStore else { throw AppServicesError.storeUnavailable }
        try await subscriptionStore.setManagementState(state, for: targets)
        notifySubscriptionDataChanged()
    }

    func confirmAutomaticRenewal(
        _ request: SubscriptionRenewalRequest,
        referenceDate: LocalDate = .today
    ) async throws -> SubscriptionRenewalPreview {
        guard let subscriptionStore else { throw AppServicesError.storeUnavailable }
        let preview = try await subscriptionStore.confirmAutomaticRenewal(
            request,
            referenceDate: referenceDate
        )
        notifySubscriptionDataChanged()
        return preview
    }

    func markAutomaticRenewalNotRenewed(
        _ request: SubscriptionNonRenewalRequest,
        referenceDate: LocalDate = .today
    ) async throws {
        guard let subscriptionStore else { throw AppServicesError.storeUnavailable }
        try await subscriptionStore.markAutomaticRenewalNotRenewed(
            request,
            referenceDate: referenceDate
        )
        subscriptionNotifications.recordHandledPeriod(
            subscriptionID: request.subscriptionID,
            expiry: request.expectedExpiry
        )
        notifySubscriptionDataChanged()
    }

    func reconcileSubscriptionNotifications(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate = .today
    ) async {
        await subscriptionNotifications.reconcile(
            subscriptions: subscriptions,
            referenceDate: referenceDate
        )
    }

    func requestSubscriptionNotificationAuthorization(
        referenceDate: LocalDate = .today
    ) async throws {
        await subscriptionNotifications.requestAuthorization()
        try await reconcileSubscriptionNotifications(referenceDate: referenceDate)
    }

    func reconcileSubscriptionNotifications(referenceDate: LocalDate = .today) async throws {
        guard let subscriptionStore else { throw AppServicesError.storeUnavailable }
        let subscriptions = try await subscriptionStore.fetchAll()
        await reconcileSubscriptionNotifications(
            subscriptions: subscriptions,
            referenceDate: referenceDate
        )
    }

    static func defaultIconStorageRoot(
        useMemoryStore: Bool,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL? {
        guard useMemoryStore else { return nil }
        return temporaryDirectory
            .appending(path: "Periodic", directoryHint: .isDirectory)
            .appending(path: "InMemoryIconCache", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    static func defaultPaymentAttachmentStorageRoot(
        useMemoryStore: Bool,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL? {
        guard useMemoryStore else { return nil }
        return temporaryDirectory
            .appending(path: "Periodic", directoryHint: .isDirectory)
            .appending(path: "InMemoryPaymentAttachments", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private var pendingIconCleanupReferences: Set<String> {
        Set(defaults.stringArray(forKey: PreferenceKey.pendingIconCleanupReferences) ?? [])
    }

    private func storePendingIconCleanupReferences(_ references: Set<String>) {
        if references.isEmpty {
            defaults.removeObject(forKey: PreferenceKey.pendingIconCleanupReferences)
        } else {
            defaults.set(
                references.sorted(),
                forKey: PreferenceKey.pendingIconCleanupReferences
            )
        }
    }

    private func retryPendingIconCleanup() async {
        let pendingReferences = pendingIconCleanupReferences
        guard !pendingReferences.isEmpty, let dataExchange else { return }
        do {
            let referencedImages = try await dataExchange.referencedIconReferences()
            let orphanedReferences = pendingReferences.subtracting(referencedImages)
            _ = try await syncBootstrapStore?.recordAssetDeletions(
                references: orphanedReferences
            )
            let failures = await appleIconCache.removeStoredImages(
                references: orphanedReferences
            )
            storePendingIconCleanupReferences(failures)
        } catch {
            AppLog.persistence.error("Failed to retry subscription icon cleanup")
        }
    }

    private var pendingPaymentAttachmentCleanupReferences: Set<String> {
        Set(
            defaults.stringArray(
                forKey: PreferenceKey.pendingPaymentAttachmentCleanupReferences
            ) ?? []
        )
    }

    private func storePendingPaymentAttachmentCleanupReferences(
        _ references: Set<String>
    ) {
        if references.isEmpty {
            defaults.removeObject(
                forKey: PreferenceKey.pendingPaymentAttachmentCleanupReferences
            )
        } else {
            defaults.set(
                references.sorted(),
                forKey: PreferenceKey.pendingPaymentAttachmentCleanupReferences
            )
        }
    }

    private func cleanPaymentAttachments(candidates: Set<String>) async {
        guard !candidates.isEmpty, let subscriptionStore else { return }
        if usesPersistentStore {
            storePendingPaymentAttachmentCleanupReferences(
                pendingPaymentAttachmentCleanupReferences.union(candidates)
            )
            await retryPendingPaymentAttachmentCleanup()
            return
        }
        do {
            let referenced = try await subscriptionStore
                .referencedPaymentAttachmentReferences()
            _ = await paymentAttachmentStore.removeStoredImages(
                references: candidates.subtracting(referenced)
            )
        } catch {
            AppLog.persistence.error("Failed to clean payment attachments")
        }
    }

    private func retryPendingPaymentAttachmentCleanup() async {
        let pendingReferences = pendingPaymentAttachmentCleanupReferences
        guard !pendingReferences.isEmpty, let subscriptionStore else { return }
        do {
            let referenced = try await subscriptionStore
                .referencedPaymentAttachmentReferences()
            let orphanedReferences = pendingReferences.subtracting(
                referenced
            )
            _ = try await syncBootstrapStore?.recordAssetDeletions(
                references: orphanedReferences
            )
            let failures = await paymentAttachmentStore.removeStoredImages(
                references: orphanedReferences
            )
            storePendingPaymentAttachmentCleanupReferences(failures)
        } catch {
            AppLog.persistence.error("Failed to retry payment attachment cleanup")
        }
    }

    private func removeOrphanedPaymentAttachments() async {
        guard let subscriptionStore else { return }
        do {
            let referenced = try await subscriptionStore
                .referencedPaymentAttachmentReferences()
            let failures = await paymentAttachmentStore.removeUnreferencedImages(
                keeping: referenced,
                modifiedBefore: Date().addingTimeInterval(-24 * 60 * 60)
            )
            guard !failures.isEmpty else { return }
            storePendingPaymentAttachmentCleanupReferences(
                pendingPaymentAttachmentCleanupReferences.union(failures)
            )
        } catch {
            AppLog.persistence.error("Failed to reconcile stored payment attachments")
        }
    }
}

private enum AppServicesError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? { "订阅数据库尚未就绪。" }
}
