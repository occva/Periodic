import Foundation
import SwiftData
import Testing
@testable import Periodic

@MainActor
struct PersistenceControllerTests {
    @Test func emptySchemaIsRejectedWithoutCreatingFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = PersistenceController(storeURL: directory.appending(path: "test.store"))

        #expect(throws: PersistenceController.StorageError.self) {
            try controller.makeContainer(schema: Schema([]))
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func inMemoryStoreDoesNotWriteToDisk() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = PersistenceController(storeURL: directory.appending(path: "test.store"))
        let container = try controller.makeContainer(schema: Schema([StorageProbe.self]), inMemory: true)
        let context = ModelContext(container)
        context.insert(StorageProbe(value: "memory"))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<StorageProbe>()) == 1)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func diskStoreCanBeReopened() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = PersistenceController(storeURL: directory.appending(path: "test.store"))
        try writeProbe(using: controller)

        let reopened = try controller.makeContainer(schema: Schema([StorageProbe.self]))
        let context = ModelContext(reopened)
        let records = try context.fetch(FetchDescriptor<StorageProbe>())
        #expect(records.map(\.value) == ["persisted"])
    }

    @Test func invalidStorageDirectoryPreservesExistingFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockingFile = directory.appending(path: "not-a-directory")
        let original = Data("keep me".utf8)
        try original.write(to: blockingFile)
        let controller = PersistenceController(storeURL: blockingFile.appending(path: "test.store"))

        #expect(throws: (any Error).self) {
            try controller.makeContainer(schema: Schema([StorageProbe.self]))
        }
        #expect(try Data(contentsOf: blockingFile) == original)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func writeProbe(using controller: PersistenceController) throws {
        let container = try controller.makeContainer(schema: Schema([StorageProbe.self]))
        let context = ModelContext(container)
        context.insert(StorageProbe(value: "persisted"))
        try context.save()
    }
}

/// Test-only model. No persistence model is shipped in the application target.
@Model
final class StorageProbe {
    var value: String

    init(value: String) {
        self.value = value
    }
}
