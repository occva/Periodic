import Foundation
import Observation
import SwiftData

/// App-wide dependencies. Window selection and presentation state stay in views.
@MainActor
@Observable
final class AppServices {
    let persistence: PersistenceController
    let subscriptionStore: SubscriptionStore?
    let templateStore: TemplateStore?
    let templateCategoryStore: TemplateCategoryStore?
    let appleIconSearch: AppleIconSearchClient
    let appleIconCache: AppleIconCache
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
        defaults: UserDefaults = .standard
    ) {
        let processArguments = ProcessInfo.processInfo.arguments
        let useMemoryStore = inMemory ?? processArguments.contains("-store-in-memory")
        let enablesSampleNotifications = useMemoryStore
            && processArguments.contains("-enable-test-notifications")
        let resolvedAppleIconCache = appleIconCache ?? AppleIconCache(
            storageRoot: Self.defaultIconStorageRoot(useMemoryStore: useMemoryStore)
        )
        self.persistence = persistence
        self.defaults = defaults
        usesPersistentStore = !useMemoryStore
        appleIconSearch = AppleIconSearchClient()
        self.appleIconCache = resolvedAppleIconCache
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
            let schema = Schema(versionedSchema: AppSchemaV2.self)
            let container = try persistence.makeContainer(
                schema: schema,
                migrationPlan: AppSchemaMigrationPlan.self,
                inMemory: useMemoryStore
            )
            modelContainer = container
            subscriptionStore = SubscriptionStore(modelContainer: container)
            templateStore = TemplateStore(modelContainer: container)
            templateCategoryStore = TemplateCategoryStore(modelContainer: container)
            builtinTemplateCategoryStore = BuiltinTemplateCategoryStore(modelContainer: container)
            dataExchange = DataExchangeService(
                store: DataExchangeStore(modelContainer: container),
                iconCache: resolvedAppleIconCache
            )
        } catch {
            modelContainer = nil
            subscriptionStore = nil
            templateStore = nil
            templateCategoryStore = nil
            builtinTemplateCategoryStore = nil
            dataExchange = nil
            initializationError = PresentedError(error, title: "无法打开订阅数据")
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
    }

    func notifySubscriptionDataChanged() {
        subscriptionDataVersion &+= 1
    }

    func notifyTemplateDataChanged() {
        templateDataVersion &+= 1
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
        if usesPersistentStore {
            let queuedReferences = pendingIconCleanupReferences.union(
                result.unreferencedIconReferences
            )
            storePendingIconCleanupReferences(queuedReferences)
            await retryPendingIconCleanup()
            pendingIconCleanupCount = pendingIconCleanupReferences.count
        } else {
            pendingIconCleanupCount = await appleIconCache.removeStoredImages(
                references: result.unreferencedIconReferences
            ).count
        }
        notifySubscriptionDataChanged()
        return SubscriptionDeletionOutcome(
            pendingIconCleanupCount: pendingIconCleanupCount
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
            let failures = await appleIconCache.removeStoredImages(
                references: orphanedReferences
            )
            storePendingIconCleanupReferences(failures)
        } catch {
            AppLog.persistence.error("Failed to retry subscription icon cleanup")
        }
    }
}

private enum AppServicesError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? { "订阅数据库尚未就绪。" }
}
