import CryptoKit
import Foundation

struct StoredIconReference: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case apple
        case user

        var prefix: String {
            switch self {
            case .apple: "apple-icon:"
            case .user: "user-icon:"
            }
        }
    }

    let source: Source
    let key: String

    var rawValue: String { source.prefix + key }

    init?(rawValue: String) {
        for source in [Source.apple, .user] where rawValue.hasPrefix(source.prefix) {
            let key = String(rawValue.dropFirst(source.prefix.count))
            guard key.count == 64, key.allSatisfy(\.isHexDigit) else { return nil }
            self.source = source
            self.key = key
            return
        }
        guard let url = URL(string: rawValue), url.scheme == "https",
              let host = url.host?.lowercased(),
              host == "mzstatic.com" || host.hasSuffix(".mzstatic.com") else { return nil }
        source = .apple
        key = SHA256.hash(data: Data(rawValue.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func normalized(_ reference: String) -> String {
        Self(rawValue: reference)?.rawValue ?? reference
    }

    static func normalized(_ references: Set<String>) -> Set<String> {
        Set(references.map { normalized($0) })
    }
}
