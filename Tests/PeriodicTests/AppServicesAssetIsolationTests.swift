import Foundation
import Testing
@testable import Periodic

@MainActor
struct AppServicesAssetIsolationTests {
    @Test func defaultTestHostUsesMemoryStorage() throws {
        let services = AppServices()
        let container = try #require(services.modelContainer)
        let configurations = container.configurations
        #expect(configurations.allSatisfy { $0.isStoredInMemoryOnly })
    }

    @Test func customDatabaseMaintenanceCannotRemoveAnotherDatabasesAssets() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStoreURL = directory.appending(path: "first.store")
        let secondStoreURL = directory.appending(path: "second.store")
        let firstRoot = try #require(AppServices.defaultIconStorageRoot(
            useMemoryStore: false, storeURL: firstStoreURL
        ))
        let secondRoot = try #require(AppServices.defaultIconStorageRoot(
            useMemoryStore: false, storeURL: secondStoreURL
        ))
        #expect(firstRoot != secondRoot)
        #expect(firstRoot.path.hasPrefix(directory.path))
        #expect(secondRoot.path.hasPrefix(directory.path))
        let suiteName = "AssetIsolationTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = AppServices(
            persistence: PersistenceController(storeURL: firstStoreURL),
            inMemory: false,
            defaults: defaults
        )
        let second = AppServices(
            persistence: PersistenceController(storeURL: secondStoreURL),
            inMemory: false,
            defaults: defaults
        )
        let image = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let icon = try await first.appleIconCache.persistImportedImage(image)
        await first.appleIconCache.releaseImportedImages([icon])
        let attachment = try await first.paymentAttachmentStore.persistImportedImage(image)
        await first.paymentAttachmentStore.releaseImportedImages([attachment])
        try ageAssets(in: firstRoot)

        try await second.prepareStoredSubscriptionData()

        #expect(try await first.appleIconCache.data(for: icon.reference) == image)
        #expect(try await first.paymentAttachmentStore.data(for: attachment.reference) == image)
    }

    private func ageAssets(in root: URL) throws {
        let enumerator = try #require(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ))
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                try FileManager.default.setAttributes(
                    [.modificationDate: Date.distantPast], ofItemAtPath: file.path
                )
            }
        }
    }
}
