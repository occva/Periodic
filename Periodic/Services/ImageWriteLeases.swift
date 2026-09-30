import Foundation

struct ImageWriteLeases {
    struct Lease: Sendable {
        let reference: String
        fileprivate let id: UUID
        fileprivate let retentionVersion: UUID
    }

    private var activeLeaseIDsByReference: [String: Set<UUID>] = [:]
    private var retentionVersionsByReference: [String: UUID] = [:]

    mutating func acquire(for reference: String) -> Lease {
        let retentionVersion = retentionVersionsByReference[reference] ?? UUID()
        retentionVersionsByReference[reference] = retentionVersion
        let lease = Lease(reference: reference, id: UUID(), retentionVersion: retentionVersion)
        activeLeaseIDsByReference[reference, default: []].insert(lease.id)
        return lease
    }

    mutating func retain(_ leases: [Lease]) {
        let references = Set(leases.filter {
            activeLeaseIDsByReference[$0.reference]?.contains($0.id) == true
        }.map(\.reference))
        for reference in references {
            retain(reference: reference)
        }
        _ = release(leases)
    }

    mutating func retain(reference: String) {
        retentionVersionsByReference[reference] = UUID()
    }

    mutating func release(_ leases: [Lease]) -> Set<String> {
        let candidates = Set(leases.filter {
            activeLeaseIDsByReference[$0.reference]?.contains($0.id) == true
                && retentionVersionsByReference[$0.reference] == $0.retentionVersion
        }.map(\.reference))
        for lease in leases {
            activeLeaseIDsByReference[lease.reference]?.remove(lease.id)
            if activeLeaseIDsByReference[lease.reference]?.isEmpty == true {
                activeLeaseIDsByReference.removeValue(forKey: lease.reference)
            }
        }
        return candidates.filter { !hasActiveLease(for: $0) }
    }

    func hasActiveLease(for reference: String) -> Bool {
        activeLeaseIDsByReference[reference] != nil
    }

    mutating func forget(_ reference: String) {
        retentionVersionsByReference.removeValue(forKey: reference)
    }
}
