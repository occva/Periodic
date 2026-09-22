import Foundation
import SwiftData

/// Container construction only: the scaffold deliberately has no domain schema.
@MainActor
struct PersistenceController {
    enum StorageError: LocalizedError {
        case emptySchema

        var errorDescription: String? {
            "尚未注册数据模型，无法创建存储容器。"
        }
    }

    let storeURL: URL

    init(storeURL: URL = AppConfiguration.storeURL) {
        self.storeURL = storeURL
    }

    func makeContainer(
        schema: Schema,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        guard !schema.entities.isEmpty else {
            throw StorageError.emptySchema
        }

        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        } else {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            configuration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        }

        // Surface errors; never silently delete a store or fall back to memory.
        return try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: [configuration]
        )
    }
}
