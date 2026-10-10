import Foundation
import SwiftData
import Testing
@testable import Periodic

@MainActor
struct IconReferenceMigrationTests {
    @Test(arguments: [false, true], [false, true])
    func deletingOneReferencePreservesSharedIcon(
        sharedWithTemplate: Bool,
        deletingLegacy: Bool
    ) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName(in: defaults)) }
        let services = makeServices(directory: directory, defaults: defaults, inMemory: true)
        let reference = "https://example.mzstatic.com/shared.png"
        let localReference = localReference(for: reference)
        let deletedReference = deletingLegacy ? reference : localReference
        let retainedReference = deletingLegacy ? localReference : reference
        try writeLegacyImage(reference, directory: directory)
        #expect(try await services.appleIconCache.data(for: reference) == imageData())
        let container = try #require(services.modelContainer)
        let target = insertSubscription(reference: deletedReference, into: container.mainContext)
        if sharedWithTemplate {
            insertTemplate(reference: retainedReference, into: container.mainContext)
        } else {
            insertSubscription(reference: retainedReference, into: container.mainContext)
        }
        try container.mainContext.save()
        let preview = try await services.previewSubscriptionDeletion(targets: [
            SubscriptionMutationTarget(id: target, expectedRevision: 1)
        ])

        let outcome = try await services.deleteSubscriptions(preview)

        #expect(outcome.pendingIconCleanupCount == 0)
        #expect(try await services.appleIconCache.data(for: localReference) == imageData())
        let exchange = try #require(services.dataExchange)
        _ = try await exchange.prepareExport()
    }

    @Test func pendingLegacyCleanupPreservesAReferencedLocalIcon() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName(in: defaults)) }
        let services = makeServices(directory: directory, defaults: defaults, inMemory: false)
        let reference = "https://example.mzstatic.com/pending.png"
        let localReference = localReference(for: reference)
        try writeLegacyImage(reference, directory: directory)
        #expect(try await services.appleIconCache.data(for: reference) == imageData())
        let container = try #require(services.modelContainer)
        insertSubscription(reference: localReference, into: container.mainContext)
        try container.mainContext.save()
        defaults.set([reference], forKey: PreferenceKey.pendingIconCleanupReferences)

        try await services.prepareStoredSubscriptionData()

        #expect(try await services.appleIconCache.data(for: localReference) == imageData())
        #expect(defaults.object(forKey: PreferenceKey.pendingIconCleanupReferences) == nil)
    }

    @Test func preparationMigratesLegacySubscriptionAndTemplateReferencesIdempotently() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName(in: defaults)) }
        let services = makeServices(directory: directory, defaults: defaults, inMemory: false)
        let reference = "https://example.mzstatic.com/migration.png"
        let localReference = localReference(for: reference)
        try writeLegacyImage(reference, directory: directory)
        let container = try #require(services.modelContainer)
        insertSubscription(reference: reference, into: container.mainContext)
        insertTemplate(reference: reference, into: container.mainContext)
        try container.mainContext.save()
        let store = try #require(services.subscriptionStore)
        let templates = try #require(services.templateStore)
        let original = try #require(try await store.fetchAll().first)
        let originalTemplate = try #require(try await templates.fetchAll().first)

        try await services.prepareStoredSubscriptionData()

        let migrated = try #require(try await store.fetchAll().first)
        let migratedTemplate = try #require(try await templates.fetchAll().first)
        #expect(migrated.iconURLString == localReference)
        #expect(migrated.revision == original.revision)
        #expect(migrated.createdAt == original.createdAt)
        #expect(migrated.updatedAt == original.updatedAt)
        #expect(migratedTemplate.iconURLString == localReference)
        #expect(migratedTemplate.revision == originalTemplate.revision)
        #expect(try await services.appleIconCache.data(for: localReference) == imageData())
        let exchange = try #require(services.dataExchange)
        _ = try await exchange.prepareExport()
        try await services.prepareStoredSubscriptionData()
        #expect(try await store.fetchAll().first == migrated)
        #expect(try await templates.fetchAll().first == migratedTemplate)
    }

    @Test func missingLegacyImagePreservesReferencesUntilMigrationCanBeRetried() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName(in: defaults)) }
        let services = makeServices(directory: directory, defaults: defaults, inMemory: false)
        let firstReference = "https://example.mzstatic.com/a-present.png"
        let missingReference = "https://example.mzstatic.com/z-missing.png"
        try writeLegacyImage(firstReference, directory: directory)
        let container = try #require(services.modelContainer)
        insertSubscription(reference: firstReference, into: container.mainContext)
        insertTemplate(reference: missingReference, into: container.mainContext)
        try container.mainContext.save()

        await #expect(throws: AppleIconCache.CacheError.self) {
            try await services.prepareStoredSubscriptionData()
        }

        let exchange = try #require(services.dataExchange)
        #expect(try await exchange.referencedIconReferences() == [firstReference, missingReference])
        #expect(try await services.appleIconCache.data(for: firstReference) == imageData())
        let session = WindowSession()
        await session.loadInitialData(using: services)
        #expect(session.loadError != nil)
        #expect(session.subscriptions.count == 1)
        try writeLegacyImage(missingReference, directory: directory)
        await session.loadInitialData(using: services)
        #expect(session.loadError == nil)
        #expect(try await exchange.referencedIconReferences() == [
            localReference(for: firstReference), localReference(for: missingReference)
        ])
        _ = try await exchange.prepareExport()
    }

    private func makeServices(
        directory: URL,
        defaults: UserDefaults,
        inMemory: Bool
    ) -> AppServices {
        AppServices(
            persistence: PersistenceController(storeURL: directory.appending(path: "fixture.store")),
            inMemory: inMemory,
            appleIconCache: AppleIconCache(
                storageRoot: directory,
                legacyStorageRoot: directory.appending(path: "Legacy")
            ),
            paymentAttachmentStore: PaymentAttachmentStore(storageRoot: directory),
            defaults: defaults
        )
    }

    @discardableResult
    private func insertSubscription(reference: String, into context: ModelContext) -> UUID {
        let input = SubscriptionCreateInput(
            id: UUID(), name: "Icon fixture", symbolName: "app", iconResourceName: nil,
            iconURLString: nil, category: .other, managementState: .active,
            billingKind: .lifetime, periodStart: nil, expiry: nil, cycleMonths: nil,
            money: Money(minorUnits: 0, currency: .cny), note: "", reminderEnabled: false
        )
        let record = SubscriptionRecord(input: input)
        record.iconURLString = reference
        context.insert(record)
        return record.id
    }

    private func insertTemplate(reference: String, into context: ModelContext) {
        let input = ServiceTemplateInput(
            id: UUID(), expectedRevision: nil, name: "Template fixture", aliases: [],
            category: .other, customCategoryID: nil, symbolName: "app", iconResourceName: nil,
            iconURLString: nil, suggestedBillingKind: .lifetime, suggestedCycleMonths: nil,
            suggestedMoney: nil, currency: .cny
        )
        let record = ServiceTemplateRecord(input: input, aliasesData: Data("[]".utf8))
        record.iconURLString = reference
        context.insert(record)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "IconReferenceMigrationTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(name, forKey: "fixtureSuiteName")
        return defaults
    }

    private func suiteName(in defaults: UserDefaults) -> String {
        defaults.string(forKey: "fixtureSuiteName") ?? ""
    }

    private func localReference(for reference: String) -> String {
        "apple-icon:" + DataPackageCodec.sha256(Data(reference.utf8))
    }

    private func writeLegacyImage(_ reference: String, directory: URL) throws {
        let legacy = directory.appending(path: "Legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let key = DataPackageCodec.sha256(Data(reference.utf8))
        try imageData().write(to: legacy.appending(path: key).appendingPathExtension("image"))
    }

    private func imageData() throws -> Data {
        try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
    }
}
