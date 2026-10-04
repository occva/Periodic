import CloudKit
import Foundation

struct CloudSyncEngineStateRepository: Sendable {
    enum RepositoryError: LocalizedError, Equatable {
        case invalidContents

        var errorDescription: String? {
            "iCloud 同步检查点无法读取，原有本地数据未被修改。"
        }
    }

    let stateURL: URL

    func load() throws -> CKSyncEngine.State.Serialization? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }
        do {
            return try PropertyListDecoder().decode(
                CKSyncEngine.State.Serialization.self,
                from: Data(contentsOf: stateURL)
            )
        } catch {
            throw RepositoryError.invalidContents
        }
    }

    func save(_ serialization: CKSyncEngine.State.Serialization) throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(serialization).write(
            to: stateURL,
            options: .atomic
        )
    }
}
