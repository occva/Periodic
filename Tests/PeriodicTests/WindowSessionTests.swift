import Foundation
import Testing
@testable import Periodic

@MainActor
struct WindowSessionTests {
    @Test func expiryFiltersRemainIndependentOfManagementState() async throws {
        let services = AppServices(inMemory: true)
        let store = try #require(services.subscriptionStore)
        let today = LocalDate.today
        let yesterday = try #require(today.addingDays(-1))
        var inputs: [SubscriptionCreateInput] = []
        for state in ManagementState.allCases {
            inputs.append(makeInput(name: "Expired", state: state, expiry: yesterday))
            inputs.append(makeInput(name: "Effective", state: state, expiry: today))
            inputs.append(makeInput(name: "Unknown", state: state, expiry: nil))
            inputs.append(makeInput(name: "Lifetime", state: state, billingKind: .lifetime, expiry: nil))
        }
        try await store.create(inputs)
        let session = WindowSession()
        await session.reload(using: services)

        for state in ManagementState.allCases {
            session.overviewManagementState = state
            for (filter, expectedName) in [
                (OverviewExpiryFilter.expired, "Expired"),
                (.effective, "Effective"),
                (.unknownDate, "Unknown"),
                (.lifetime, "Lifetime"),
            ] {
                session.overviewExpiryFilter = filter
                #expect(session.filteredItems.map(\.name) == [expectedName])
                #expect(session.filteredItems.allSatisfy { $0.managementState == state })
            }
        }
        session.clearOverviewFilters()
        #expect(session.filteredItems.count == inputs.count)
    }

    private func makeInput(
        name: String,
        state: ManagementState,
        billingKind: BillingKind = .recurring,
        expiry: LocalDate?
    ) -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: UUID(),
            name: name,
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: state,
            billingKind: billingKind,
            periodStart: nil,
            expiry: expiry,
            cycleMonths: billingKind == .recurring ? 1 : nil,
            money: Money(minorUnits: 1_999, currency: .usd),
            note: "",
            reminderEnabled: false
        )
    }
}
