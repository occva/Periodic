import CryptoKit
import Foundation
import Testing
@testable import Periodic

struct CloudImageAssetStagerTests {
    @Test func validatesHashDeduplicatesAndRemovesAfterLastLease() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        let hash = Self.sha256(data)
        let stager = CloudImageAssetStager(stagingRoot: root)

        let first = try await stager.stage(
            data: data,
            expectedContentHash: hash
        )
        let second = try await stager.stage(
            data: data,
            expectedContentHash: hash
        )

        #expect(first.fileURL == second.fileURL)
        #expect(first.format == .png)
        #expect(try await stager.data(for: first) == data)

        await stager.release([first])
        #expect(FileManager.default.fileExists(atPath: second.fileURL.path))
        await stager.release([second])
        #expect(!FileManager.default.fileExists(atPath: second.fileURL.path))
    }

    @Test func rejectsContentWhoseHashDoesNotMatchMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        let stager = CloudImageAssetStager(stagingRoot: root)

        await #expect(throws: CloudImageAssetStager.StagingError.hashMismatch) {
            try await stager.stage(
                data: data,
                expectedContentHash: String(repeating: "a", count: 64)
            )
        }
        let stagedFiles =
            (try? FileManager.default.contentsOfDirectory(atPath: root.path))
            ?? []
        #expect(stagedFiles.isEmpty)
    }

    @Test func rejectsInvalidImageBeforeWritingStagingFile() async {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("not-an-image".utf8)
        let stager = CloudImageAssetStager(stagingRoot: root)

        await #expect(throws: CloudImageAssetStager.StagingError.invalidImage) {
            try await stager.stage(
                data: data,
                expectedContentHash: Self.sha256(data)
            )
        }
    }

    @Test func reacquiresAStagedDownloadAfterRestart() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try #require(Data(base64Encoded: Self.onePixelPNG))
        let hash = Self.sha256(data)
        let initialStager = CloudImageAssetStager(stagingRoot: root)
        _ = try await initialStager.stage(
            data: data,
            expectedContentHash: hash
        )
        let reopenedStager = CloudImageAssetStager(stagingRoot: root)

        let recovered = try await reopenedStager.acquireExisting(
            metadata: CloudAssetMetadata(
                contentHash: hash,
                format: .png,
                byteCount: data.count
            )
        )

        #expect(try await reopenedStager.data(for: recovered) == data)
        await reopenedStager.release([recovered])
        #expect(!FileManager.default.fileExists(atPath: recovered.fileURL.path))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
