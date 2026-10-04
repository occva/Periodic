import Foundation
import SwiftData

@ModelActor
actor CloudSyncMetadataStore {
    private var datasetAccess = DatasetAccessCoordinator()

    init(
        modelContainer: ModelContainer,
        datasetAccess: DatasetAccessCoordinator
    ) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.datasetAccess = datasetAccess
    }

    func apply(_ descriptor: DatasetDescriptor) async throws {
        let lease = try await datasetAccess.acquireWrite()
        do {
            _ = try DatasetMetadata.prepare(
                in: modelContext,
                descriptor: descriptor
            )
            await datasetAccess.releaseWrite(lease)
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }
}
