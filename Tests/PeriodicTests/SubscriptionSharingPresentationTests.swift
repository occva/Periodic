import Foundation
import Testing
@testable import Periodic

struct SubscriptionSharingPresentationTests {
    @Test(arguments: [
        (CurrencyCode.cny, Decimal(-2) / 100),
        (.jpy, Decimal(-2)),
        (.kwd, Decimal(-2) / 1_000),
    ])
    func completeQuotesKeepCurrencyPrecisionAndSignedDifference(
        currency: CurrencyCode,
        expectedDifference: Decimal
    ) {
        let mine = Money(minorUnits: 1, currency: currency)
        let plan = SubscriptionSharingPlan(
            role: .organizer,
            purchaseMoney: Money(minorUnits: 4, currency: currency),
            members: [member(money: mine)]
        )
        let total = Money(minorUnits: 2, currency: currency)
        #expect(SubscriptionSharingQuoteSummary(plan: plan, myMoney: mine) == .complete(
            total: total,
            purchaseDifference: expectedDifference
        ))
    }

    @Test func partialQuotesReportUnknownPeopleWithoutShowingAPartialTotal() {
        let zero = Money(minorUnits: 0, currency: .cny)
        let plan = SubscriptionSharingPlan(
            role: .participant,
            purchaseMoney: nil,
            members: [member(money: nil), member(money: zero), member(money: nil)]
        )
        #expect(SubscriptionSharingQuoteSummary(plan: plan, myMoney: zero)
            == .incomplete(unknownMemberCount: 2))
    }

    @Test func zeroQuotesRemainCompleteWithoutInventingAPurchasePrice() {
        let zero = Money(minorUnits: 0, currency: .cny)
        let plan = SubscriptionSharingPlan(
            role: .participant,
            purchaseMoney: nil,
            members: [member(money: zero)]
        )
        #expect(SubscriptionSharingQuoteSummary(plan: plan, myMoney: zero)
            == .complete(total: zero, purchaseDifference: nil))
    }

    @Test func invalidQuotesShowFailureInsteadOfZeroOrAPartialTotal() {
        let mine = Money(minorUnits: 1, currency: .cny)
        let plans = [
            SubscriptionSharingPlan(
                role: .participant,
                purchaseMoney: nil,
                members: [member(money: Money(minorUnits: Int64.max, currency: .cny))]
            ),
            SubscriptionSharingPlan(
                role: .participant,
                purchaseMoney: Money(minorUnits: 10, currency: .usd),
                members: [member(money: mine)]
            ),
        ]
        for plan in plans {
            #expect(SubscriptionSharingQuoteSummary(plan: plan, myMoney: mine) == .invalid)
        }
    }

    @Test func removingSelectedMemberPreservesOtherIdentitiesAndDraftAmounts() throws {
        let original = SubscriptionSharingPlan(
            role: .participant,
            purchaseMoney: nil,
            members: [
                member(name: "First", money: Money(minorUnits: 100, currency: .cny)),
                member(name: "Middle", money: nil),
                member(name: "Last", money: Money(minorUnits: 300, currency: .cny)),
            ]
        )
        var draft = SubscriptionSharingDraft(plan: original)
        draft.removeMember(id: original.members[1].id)
        #expect(draft.memberCount == 3)
        #expect(draft.members.map(\.id) == [original.members[0].id, original.members[2].id])
        #expect(draft.members.map(\.amountText) == ["1.00", "3.00"])
        draft.removeMember(id: UUID())
        #expect(draft.memberCount == 3)
        #expect(original.members.count == 3)
        let saved = try #require(try draft.plan(myMoney: Money(minorUnits: 200, currency: .cny)))
        #expect(saved.members.map(\.name) == ["First", "Last"])
    }

    @Test func removalCannotReduceCarpoolBelowTwoPeople() {
        var draft = SubscriptionSharingDraft()
        let memberID = draft.members[0].id
        draft.removeMember(id: memberID)
        draft.removeMember(id: UUID())
        #expect(draft.memberCount == 2)
        #expect(draft.members[0].id == memberID)
    }

    @Test func addingMemberReturnsNewIdentityAndPreservesExistingInputs() {
        var draft = SubscriptionSharingDraft()
        draft.members[0].name = "Original member"
        draft.members[0].amountText = "15.00"
        let originalID = draft.members[0].id
        let addedID = draft.addMember()
        #expect(draft.memberCount == 3)
        #expect(draft.members[0].id == originalID)
        #expect(draft.members[0].name == "Original member")
        #expect(draft.members[0].amountText == "15.00")
        #expect(draft.members[1].id == addedID)
        #expect(addedID != originalID)
        #expect(draft.members[1].amountText.isEmpty)
    }

    @Test func participantSavesOnlyPersonalPriceWithSelectedHeadcount() throws {
        var draft = SubscriptionSharingDraft()
        draft.isEnabled = true
        draft.setMemberCount(6)
        let mine = Money(minorUnits: 1_500, currency: .cny)
        let plan = try #require(try draft.plan(myMoney: mine))
        #expect(plan.role == .participant)
        #expect(plan.memberCount == 6)
        #expect(plan.purchaseMoney == nil)
        #expect(plan.members.allSatisfy { $0.money == nil })
        #expect(plan.defaultPaymentMoney(myMoney: mine) == mine)
    }

    @Test func organizerRequiresEachMemberPriceAndAcceptsFreeMembers() throws {
        var draft = SubscriptionSharingDraft()
        draft.isEnabled = true
        draft.role = .organizer
        draft.purchaseAmountText = "30"
        draft.members[0].name = "Member"
        #expect(throws: SubscriptionSharingDraftError.missingMemberPrice("Member")) {
            try draft.plan(myMoney: Money(minorUnits: 1_500, currency: .cny))
        }
        draft.members[0].name = " \n"
        #expect(throws: SubscriptionSharingError.self) {
            try draft.plan(myMoney: Money(minorUnits: 1_500, currency: .cny))
        }
        draft.members[0].name = "Member"
        draft.members[0].amountText = "0"
        let plan = try #require(try draft.plan(myMoney: Money(minorUnits: 1_500, currency: .cny)))
        #expect(plan.members[0].money == Money(minorUnits: 0, currency: .cny))
    }

    @Test func headcountChangesPreserveRetainedMembersAndMinimum() {
        var draft = SubscriptionSharingDraft()
        draft.members[0].name = "Retained"
        draft.members[0].amountText = "15.00"
        let retainedID = draft.members[0].id
        draft.setMemberCount(6)
        #expect(Set(draft.members.map(\.id)).count == 5)
        draft.setMemberCount(3)
        #expect(draft.memberCount == 3)
        #expect(draft.members[0].id == retainedID)
        #expect(draft.members[0].amountText == "15.00")
        draft.setMemberCount(0)
        #expect(draft.memberCount == 2)
        #expect(draft.members[0].id == retainedID)
    }

    @Test func switchingRolesPreservesExistingPriceDrafts() throws {
        let original = SubscriptionSharingPlan(
            role: .organizer,
            purchaseMoney: Money(minorUnits: 3_000, currency: .cny),
            members: [member(name: "Member", money: Money(minorUnits: 1_500, currency: .cny))]
        )
        var draft = SubscriptionSharingDraft(plan: original)
        draft.role = .participant
        let participant = try #require(try draft.plan(myMoney: Money(minorUnits: 1_500, currency: .cny)))
        #expect(participant.purchaseMoney == original.purchaseMoney)
        #expect(participant.members == original.members)
        draft.role = .organizer
        let organizer = try #require(try draft.plan(myMoney: Money(minorUnits: 1_500, currency: .cny)))
        #expect(organizer == original)
    }

    @Test func legacyOrganizerMissingMemberPriceRemainsReadableUntilEdited() throws {
        let legacy = SubscriptionSharingPlan(
            role: .organizer,
            purchaseMoney: Money(minorUnits: 3_000, currency: .cny),
            members: [member(name: "Member", money: nil)]
        )
        let mine = Money(minorUnits: 1_500, currency: .cny)
        try legacy.validate(myMoney: mine)
        let draft = SubscriptionSharingDraft(plan: legacy)
        #expect(throws: SubscriptionSharingDraftError.missingMemberPrice("Member")) {
            try draft.plan(myMoney: mine)
        }
    }

    private func member(name: String = "Member", money: Money?) -> SubscriptionSharingMember {
        .init(id: UUID(), name: name, money: money)
    }

}
