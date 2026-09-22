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
    let builtinTemplates: BuiltinTemplateCatalog?
    let modelContainer: ModelContainer?
    private(set) var initializationError: PresentedError?
    private(set) var builtinTemplateError: PresentedError?
    private(set) var subscriptionDataVersion = 0
    private(set) var templateDataVersion = 0
    private var didPrepareDevelopmentData = false

    init(
        persistence: PersistenceController = PersistenceController(),
        inMemory: Bool? = nil
    ) {
        self.persistence = persistence
        appleIconSearch = AppleIconSearchClient()
        appleIconCache = AppleIconCache()
        do {
            builtinTemplates = try BuiltinTemplateCatalog.load()
        } catch {
            builtinTemplates = nil
            builtinTemplateError = PresentedError(error, title: "无法读取内置模板")
        }
        let useMemoryStore = inMemory ?? ProcessInfo.processInfo.arguments.contains("-store-in-memory")

        do {
            let schema = Schema([
                SubscriptionRecord.self,
                SubscriptionPeriodRecord.self,
                ServiceTemplateRecord.self,
                TemplateCategoryRecord.self,
            ])
            let container = try persistence.makeContainer(schema: schema, inMemory: useMemoryStore)
            modelContainer = container
            subscriptionStore = SubscriptionStore(modelContainer: container)
            templateStore = TemplateStore(modelContainer: container)
            templateCategoryStore = TemplateCategoryStore(modelContainer: container)
        } catch {
            modelContainer = nil
            subscriptionStore = nil
            templateStore = nil
            templateCategoryStore = nil
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
        let subscriptions = DevelopmentSubscriptionDataset.make(referenceDate: referenceDate)
        try await subscriptionStore.create(
            subscriptions,
            additionalPeriods: DevelopmentSubscriptionDataset.makeHistoricalPeriods(
                for: subscriptions
            )
        )
        #endif
    }

    func notifySubscriptionDataChanged() {
        subscriptionDataVersion &+= 1
    }

    func notifyTemplateDataChanged() {
        templateDataVersion &+= 1
    }
}
