import Testing
@testable import Periodic

struct ImageWriteLeasesTests {
    @Test func sharedImageIsDiscardableOnlyAfterLastOwnerReleases() {
        var leases = ImageWriteLeases()
        let first = leases.acquire(for: "shared")
        let second = leases.acquire(for: "shared")

        #expect(leases.release([first]).isEmpty)
        #expect(leases.hasActiveLease(for: "shared"))
        #expect(leases.release([second]) == ["shared"])
        #expect(!leases.hasActiveLease(for: "shared"))
    }

    @Test func commitInvalidatesAnOlderRollbacksDeletionAuthority() {
        var leases = ImageWriteLeases()
        let pendingImport = leases.acquire(for: "shared")
        let committedEditor = leases.acquire(for: "shared")

        leases.retain([committedEditor])

        #expect(leases.release([pendingImport]).isEmpty)
        #expect(!leases.hasActiveLease(for: "shared"))
    }

    @Test func localSelectionInvalidatesAnOlderRollbacksDeletionAuthority() {
        var leases = ImageWriteLeases()
        let pendingImport = leases.acquire(for: "shared")

        leases.retain(reference: "shared")

        #expect(leases.release([pendingImport]).isEmpty)
    }

    @Test func releasedTokenCannotDeleteAReplacementWithTheSameReference() {
        var leases = ImageWriteLeases()
        let original = leases.acquire(for: "shared")
        #expect(leases.release([original]) == ["shared"])
        leases.forget("shared")
        let replacement = leases.acquire(for: "shared")

        #expect(leases.release([original]).isEmpty)
        #expect(leases.hasActiveLease(for: "shared"))
        #expect(leases.release([replacement]) == ["shared"])
    }
}
