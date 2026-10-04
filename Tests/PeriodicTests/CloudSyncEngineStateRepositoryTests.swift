import Foundation
import Testing
@testable import Periodic

struct CloudSyncEngineStateRepositoryTests {
    @Test func rejectsCorruptedStateWithoutReplacingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.plist")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let corrupted = Data("not a plist".utf8)
        try corrupted.write(to: stateURL)
        let repository = CloudSyncEngineStateRepository(
            stateURL: stateURL
        )

        #expect(
            throws: CloudSyncEngineStateRepository.RepositoryError
                .invalidContents
        ) {
            try repository.load()
        }
        #expect(try Data(contentsOf: stateURL) == corrupted)
    }
}

struct CloudAccountIdentityRepositoryTests {
    @Test func roundTripsValidatedFingerprint() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CloudAccountIdentityRepository(
            identityURL: directory.appending(path: "account-identity")
        )
        let fingerprint = String(repeating: "a", count: 64)

        try repository.save(fingerprint)

        #expect(try repository.load() == fingerprint)
    }

    @Test func corruptedFingerprintIsNotSilentlyReplaced() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appending(path: "account-identity")
        let original = Data("invalid".utf8)
        try original.write(to: url)
        let repository = CloudAccountIdentityRepository(
            identityURL: url
        )

        #expect(
            throws: CloudAccountIdentityRepository.RepositoryError
                .invalidContents
        ) {
            try repository.load()
        }
        #expect(try Data(contentsOf: url) == original)
    }
}
