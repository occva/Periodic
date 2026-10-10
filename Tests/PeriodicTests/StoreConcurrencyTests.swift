import Foundation
import SwiftData
import Testing
@testable import Periodic

@MainActor
struct StoreConcurrencyTests {
    @Test(arguments: [false, true])
    func concurrentImportCannotOverwriteASuccessfulEdit(persistent: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController(
            storeURL: directory.appending(path: "race.sqlite")
        ).makeContainer(
            schema: Schema(versionedSchema: AppSchemaV6.self),
            migrationPlan: AppSchemaMigrationPlan.self,
            inMemory: !persistent
        )
        let database = DatabaseSession(modelContainer: container)
        let subscriptions = SubscriptionStore(database: database)
        let exchange = DataExchangeStore(database: database)
        let isRunningOnMainThread = await subscriptions.isRunningOnMainThread()
        #expect(!isRunningOnMainThread)
        let input = makeInput(name: "Original")
        _ = try await subscriptions.create(input)
        var imported = try await exchange.snapshot()
        let digest = try await exchange.digest()
        let record = try #require(imported.subscriptions.first)
        let fields = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(record)
        ) as? [String: Any])
        imported.subscriptions = try (0..<1_001).map { index in
            var values = fields
            values["id"] = index == 0 ? input.id.uuidString : UUID().uuidString
            values["name"] = index == 0 ? "Imported" : "Additional \(index)"
            return try JSONDecoder().decode(
                DataPackageSubscription.self,
                from: JSONSerialization.data(withJSONObject: values)
            )
        }
        let snapshot = imported
        let importer = Task.detached {
            do {
                _ = try await exchange.execute(
                    imported: snapshot,
                    expectedDigest: digest,
                    conflictResolution: .useImported
                )
                return true
            } catch DataExchangeError.stalePlan {
                return false
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        let editCommitted: Bool
        do {
            try await subscriptions.update(
                makeInput(id: input.id, name: "Concurrent edit"),
                expectedRevision: 1,
                historyPolicy: .currentOnly
            )
            editCommitted = true
        } catch SubscriptionStore.StoreError.revisionConflict {
            editCommitted = false
        }
        let importCommitted = try await importer.value
        let current = try #require(try await subscriptions.fetchAll().first { $0.id == input.id })
        #expect(editCommitted != importCommitted)
        #expect(current.name == (editCommitted ? "Concurrent edit" : "Imported"))
        #expect(current.revision == 2)
    }

    private func makeInput(id: UUID = UUID(), name: String) -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: id,
            name: name,
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: nil,
            expiry: nil,
            cycleMonths: 1,
            money: Money(minorUnits: 100, currency: .cny),
            note: "",
            reminderEnabled: false
        )
    }
}

extension SubscriptionStore {
    fileprivate func isRunningOnMainThread() -> Bool { Thread.isMainThread }
}
