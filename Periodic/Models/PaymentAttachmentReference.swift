import Foundation

enum PaymentAttachmentReference {
    static let prefix = "payment-attachment:"

    static func make(contentHash: String) -> String {
        prefix + contentHash
    }

    static func contentHash(from reference: String) -> String? {
        guard reference.hasPrefix(prefix) else { return nil }
        let hash = String(reference.dropFirst(prefix.count))
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        return hash
    }

    static func isValid(_ reference: String) -> Bool {
        contentHash(from: reference) != nil
    }

    static func removingDuplicates(_ references: [String]) -> [String] {
        var seen = Set<String>()
        return references.filter { seen.insert($0).inserted }
    }
}
