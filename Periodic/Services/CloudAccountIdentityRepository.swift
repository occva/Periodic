import Foundation

struct CloudAccountIdentityRepository: Sendable {
    enum RepositoryError: LocalizedError, Equatable {
        case invalidContents

        var errorDescription: String? {
            "无法读取 iCloud 账号绑定信息，已暂停同步以保护现有数据。"
        }
    }

    let identityURL: URL

    func load() throws -> String? {
        guard FileManager.default.fileExists(atPath: identityURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: identityURL)
        guard let value = String(data: data, encoding: .utf8),
              isValid(value) else {
            throw RepositoryError.invalidContents
        }
        return value.lowercased()
    }

    func save(_ fingerprint: String) throws {
        guard isValid(fingerprint) else {
            throw RepositoryError.invalidContents
        }
        try FileManager.default.createDirectory(
            at: identityURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(fingerprint.lowercased().utf8)
            .write(to: identityURL, options: .atomic)
    }

    private func isValid(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }
}
