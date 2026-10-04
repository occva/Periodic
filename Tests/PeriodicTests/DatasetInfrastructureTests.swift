import Foundation
import SwiftData
import Testing
@testable import Periodic

struct DatasetInfrastructureTests {
    @Test func writeReleaseHandlerRunsAfterAWriteLeaseEnds() async throws {
        let coordinator = DatasetAccessCoordinator()
        let counter = ReleaseCounter()
        await coordinator.setWriteReleaseHandler {
            Task {
                await counter.increment()
            }
        }
        let lease = try await coordinator.acquireWrite()
        await coordinator.releaseWrite(lease)

        for _ in 0..<20 where await counter.value == 0 {
            await Task.yield()
        }
        #expect(await counter.value == 1)
    }

    @Test func descriptorRepositoryRoundTripsValidatedDescriptor() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "active-dataset.json")
        let repository = DatasetDescriptorRepository(descriptorURL: url)
        let descriptor = DatasetDescriptor(
            datasetID: UUID(),
            storageKind: .iCloud,
            cloudZoneName: "Periodic",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastSuccessfulSyncAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        try repository.save(descriptor)

        #expect(try repository.load() == descriptor)
    }

    @Test func invalidDescriptorDoesNotGetSilentlyReplaced() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appending(path: "active-dataset.json")
        let original = Data("not-json".utf8)
        try original.write(to: url)
        let repository = DatasetDescriptorRepository(descriptorURL: url)

        #expect(throws: DatasetDescriptorError.invalidContents) {
            try repository.load()
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func deviceIdentityIsStableAndCorruptionIsNotReplaced() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "device-identity.json")
        let repository = DeviceIdentityRepository(identityURL: url)

        let first = try repository.loadOrCreate(
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(try repository.loadOrCreate() == first)

        let invalid = Data("not-json".utf8)
        try invalid.write(to: url, options: .atomic)
        #expect(throws: DeviceIdentityError.invalidContents) {
            try repository.loadOrCreate()
        }
        #expect(try Data(contentsOf: url) == invalid)
    }

    @MainActor
    @Test func maintenanceLeaseBlocksWritesAndStoreRevisionSpansStores() async throws {
        let container = try makeContainer()
        let descriptor = DatasetDescriptor.local(datasetID: UUID())
        let access = DatasetAccessCoordinator(descriptor: descriptor)
        let categoryStore = TemplateCategoryStore(
            modelContainer: container,
            datasetAccess: access
        )
        let builtinStore = BuiltinTemplateCategoryStore(
            modelContainer: container,
            datasetAccess: access
        )
        let maintenance = try await access.beginMaintenance()
        let categoryID = UUID()

        do {
            try await categoryStore.save(
                TemplateCategoryInput(
                    id: categoryID,
                    expectedRevision: nil,
                    name: "同步分类"
                )
            )
            Issue.record("维护期间不应允许写入")
        } catch let error as DatasetAccessError {
            #expect(error == .maintenanceInProgress)
        }

        await access.endMaintenance(maintenance)
        try await categoryStore.save(
            TemplateCategoryInput(
                id: categoryID,
                expectedRevision: nil,
                name: "同步分类"
            )
        )
        try await builtinStore.assign(
            .builtin(.tools),
            toBuiltinTemplate: "sync-test"
        )

        let context = ModelContext(container)
        let metadata = try context.fetch(
            FetchDescriptor<DatasetMetadataRecord>()
        )
        #expect(metadata.count == 1)
        #expect(metadata.first?.datasetID == descriptor.datasetID)
        #expect(metadata.first?.storeRevision == 2)
    }

    @Test func maintenanceCannotStartDuringAnActiveWriteLease() async throws {
        let access = DatasetAccessCoordinator()
        let write = try await access.acquireWrite()

        do {
            _ = try await access.beginMaintenance()
            Issue.record("活跃写入期间不应开始维护")
        } catch let error as DatasetAccessError {
            #expect(error == .writeInProgress)
        }

        await access.releaseWrite(write)
        let maintenance = try await access.beginMaintenance()
        #expect(await access.snapshot().isMaintenanceActive)
        await access.endMaintenance(maintenance)
    }

    @Test func writeLeasesAreSerializedInArrivalOrder() async throws {
        let access = DatasetAccessCoordinator()
        let first = try await access.acquireWrite()
        let secondTask = Task {
            try await access.acquireWrite()
        }
        for _ in 0..<20 {
            if await access.snapshot().pendingWriteCount > 0 {
                break
            }
            await Task.yield()
        }

        let queued = await access.snapshot()
        #expect(queued.activeWriteCount == 1)
        #expect(queued.pendingWriteCount == 1)

        await access.releaseWrite(first)
        let second = try await secondTask.value
        let resumed = await access.snapshot()
        #expect(resumed.activeWriteCount == 1)
        #expect(resumed.pendingWriteCount == 0)
        await access.releaseWrite(second)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController().makeContainer(
            schema: Schema(versionedSchema: AppSchemaV9.self),
            inMemory: true
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}

private actor ReleaseCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
