import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Periodic

struct SubscriptionSharingPeriodEditingTests {
    @Test(arguments: [
        ("2026-10-01", "2026-10-31", "2026-11-01", "2026-11-30"),
        ("2024-01-01", "2024-01-31", "2024-02-01", "2024-02-29"),
        ("2026-12-01", "2026-12-31", "2027-01-01", "2027-01-31"),
    ])
    func nextPeriodCopiesQuotesAndUsesInclusiveCalendarDates(
        start: String, end: String, nextStart: String, nextEnd: String
    ) throws {
        let subscription = try subscription(start: start, end: end)
        let previous = period(subscription: subscription)
        let draft = try SubscriptionSharingPeriodDraft(addingTo: subscription, after: previous)
        let input = try draft.addInput()
        #expect(input.period.id != previous.id)
        #expect(input.period.start == (try LocalDate(iso8601Text: nextStart)))
        #expect(input.period.end == (try LocalDate(iso8601Text: nextEnd)))
        #expect(input.period.sharing == previous.sharing)
        #expect(input.period.money == previous.money)
        #expect(input.expectedSubscriptionRevision == subscription.revision)
    }

    @Test func customPeriodRepeatsCalendarDayCoverageAndUnrecordedPlanStartsToday() throws {
        let subscription = try subscription(start: "2026-10-01", end: "2026-10-03")
        let previous = period(subscription: subscription, cycleMonths: nil)
        let next = try SubscriptionSharingPeriodDraft(addingTo: subscription, after: previous).addInput()
        #expect(next.period.start == (try LocalDate(iso8601Text: "2026-10-04")))
        #expect(next.period.end == (try LocalDate(iso8601Text: "2026-10-06")))
        #expect(next.period.cycleMonths == nil)

        let referenceDate = try LocalDate(iso8601Text: "2026-11-10")
        let first = try SubscriptionSharingPeriodDraft(
            addingTo: subscription,
            after: nil,
            referenceDate: referenceDate
        ).addInput()
        #expect(first.period.start == referenceDate)
        #expect(first.period.end == (try LocalDate(iso8601Text: "2026-12-09")))
    }

    @Test func unrecordedCustomPlanUsesCurrentCoverageWithoutInventingAMonth() throws {
        let referenceDate = try LocalDate(iso8601Text: "2026-11-10")
        let configured = try subscription(
            start: "2026-10-01",
            end: "2026-10-03",
            cycleMonths: nil
        )
        let inherited = try SubscriptionSharingPeriodDraft(
            addingTo: configured,
            after: nil,
            referenceDate: referenceDate
        ).addInput()
        #expect(inherited.period.start == referenceDate)
        #expect(inherited.period.end == (try LocalDate(iso8601Text: "2026-11-12")))

        let incomplete = try subscription(
            start: nil,
            end: nil,
            cycleMonths: nil
        )
        let singleDay = try SubscriptionSharingPeriodDraft(
            addingTo: incomplete,
            after: nil,
            referenceDate: referenceDate
        ).addInput()
        #expect(singleDay.period.start == referenceDate)
        #expect(singleDay.period.end == referenceDate)
    }

    @Test func participantCanReduceHeadcountWithoutChangingSourceOrOtherQuotes() throws {
        let subscription = try subscription(role: .participant)
        let original = period(subscription: subscription)
        var draft = try SubscriptionSharingPeriodDraft(period: original, expectedRevision: 7)
        draft.sharing.setMemberCount(4)
        draft.period.amountText = "15.00"
        let input = try draft.updateInput()
        guard case .replace(let updated) = input.sharingUpdate else {
            Issue.record("本期编辑必须带有独立拼车快照")
            return
        }
        #expect(updated.memberCount == 4)
        #expect(updated.members.allSatisfy { $0.money == nil })
        #expect(updated.members.map(\.id) == Array(original.sharing?.members.prefix(3).map(\.id) ?? []))
        #expect(original.sharing?.memberCount == 5)
        #expect(input.money == Money(minorUnits: 1_500, currency: .cny))
        #expect(input.expectedSubscriptionRevision == 7)
    }

    @Test func draftRejectsReversedDatesMissingQuotesAndCurrencyPrecision() throws {
        let subscription = try subscription()
        var draft = try SubscriptionSharingPeriodDraft(period: period(subscription: subscription), expectedRevision: 1)
        draft.period.startDate = try LocalDate(iso8601Text: "2026-11-01").date()
        #expect(throws: (any Error).self) { try draft.updateInput() }
        draft.period.startDate = try LocalDate(iso8601Text: "2026-10-01").date()
        draft.sharing.members[0].amountText = ""
        #expect(throws: SubscriptionSharingDraftError.self) { try draft.updateInput() }
        draft.sharing.members[0].amountText = "0"
        #expect(try draft.updateInput().money == subscription.money)
        draft.period.currency = .jpy
        draft.period.amountText = "1.1"
        #expect(throws: Money.ValidationError.precision(0)) { try draft.updateInput() }
    }

    @Test func periodKindChangesSuggestDatesAndOverlapUsesInclusiveBoundaries() throws {
        let subscription = try subscription()
        let original = period(subscription: subscription)
        var next = try SubscriptionSharingPeriodDraft(addingTo: subscription, after: original)
        #expect(next.overlappingPeriods(in: [original]).isEmpty)
        next.period.startDate = try #require(original.end).date()
        #expect(next.overlappingPeriods(in: [original]).count == 1)
        var edit = try SubscriptionSharingPeriodDraft(period: original, expectedRevision: 1)
        #expect(edit.overlappingPeriods(in: [original]).isEmpty)
        edit.selectKind(.lifetime)
        #expect(edit.period.endDate == LocalDate.defaultLifetimeHistoryEnd.date())
        edit.selectKind(.quarterly)
        #expect(LocalDate(edit.period.endDate) == (try LocalDate(iso8601Text: "2026-12-31")))
        edit.selectKind(.custom)
        #expect(LocalDate(edit.period.endDate) == (try LocalDate(iso8601Text: "2026-12-31")))
    }

    @Test func selectionUsesMatchingSnapshotAndPreservesHistoryWhenCurrentSharingIsDisabled() throws {
        let subscription = try subscription()
        let current = period(subscription: subscription)
        let nextDraft = try SubscriptionSharingPeriodDraft(addingTo: subscription, after: current)
        let next = period(input: try nextDraft.addInput().period)
        #expect(SubscriptionSharingPeriodSelection.initial(
            subscription: subscription, periods: [current, next]
        ) == .period(current.id))
        let disabled = try self.subscription(id: subscription.id, isSharingEnabled: false)
        #expect(SubscriptionSharingPeriodSelection.initial(
            subscription: disabled, periods: [current, next],
            referenceDate: try LocalDate(iso8601Text: "2026-11-10")
        ) == .period(next.id))
    }

    @MainActor
    @Test func fivePeopleThenFourPeopleRemainIndependentAndHistoricalEditsPreserveCurrentPlan() async throws {
        let (store, subscription) = try await storedSubscription()
        let first = try #require(try await store.fetchPeriods(for: subscription.id).first)
        var next = try SubscriptionSharingPeriodDraft(addingTo: subscription, after: first)
        next.sharing.removeMember(id: next.sharing.members[1].id)
        next.period.amountText = "30"
        try await store.addPeriod(next.addInput())
        var detail = try await store.fetchDetail(for: subscription.id)
        #expect(detail.periods.map { $0.sharing?.memberCount } == [5, 4])
        #expect(detail.subscription.sharing == subscription.sharing)
        #expect(detail.subscription.money == subscription.money)
        #expect(detail.subscription.periodStart == subscription.periodStart)
        #expect(detail.subscription.expiry == subscription.expiry)
        #expect(detail.payments.isEmpty)
        let second = try #require(detail.periods.last)
        var edit = try SubscriptionSharingPeriodDraft(period: second, expectedRevision: detail.subscription.revision)
        edit.sharing.members[0].amountText = "12"
        try await store.updatePeriod(edit.updateInput())
        detail = try await store.fetchDetail(for: subscription.id)
        #expect(detail.periods.first == first)
        #expect(detail.periods.last?.sharing?.members[0].money == Money(minorUnits: 1_200, currency: .cny))
        #expect(detail.subscription.sharing == subscription.sharing)
        #expect(detail.subscription.revision == 3)
        #expect(detail.payments.isEmpty)
        await #expect(throws: SubscriptionStore.StoreError.revisionConflict) {
            try await store.updatePeriod(edit.updateInput())
        }
        #expect(try await store.fetchPeriods(for: subscription.id).count == 2)
    }

    @MainActor
    @Test func invalidSnapshotRollsBackAndOrdinaryPeriodEditPreservesSharing() async throws {
        let (store, subscription) = try await storedSubscription()
        let original = try #require(try await store.fetchPeriods(for: subscription.id).first)
        let invalid = SubscriptionSharingPlan(
            role: .organizer, purchaseMoney: Money(minorUnits: 1, currency: .usd),
            members: original.sharing?.members ?? []
        )
        await #expect(throws: SubscriptionSharingError.self) {
            try await store.updatePeriod(.init(
                original: original, expectedSubscriptionRevision: 1,
                billingKind: original.billingKind, cycleMonths: original.cycleMonths,
                start: original.start, end: original.end,
                money: Money(minorUnits: 9_900, currency: .cny), sharingUpdate: .replace(invalid)
            ))
        }
        var detail = try await store.fetchDetail(for: subscription.id)
        #expect(detail.periods == [original])
        #expect(detail.subscription.revision == 1)
        try await store.updatePeriod(.init(
            original: original, expectedSubscriptionRevision: 1,
            billingKind: original.billingKind, cycleMonths: original.cycleMonths,
            start: original.start, end: original.end, money: Money(minorUnits: 9_900, currency: .cny)
        ))
        detail = try await store.fetchDetail(for: subscription.id)
        #expect(detail.periods.first?.sharing == original.sharing)
        #expect(detail.periods.first?.money == Money(minorUnits: 9_900, currency: .cny))
    }

    @MainActor
    @Test func participantPeriodsSaveTheirOwnHeadcountAndPersonalPrice() async throws {
        let (store, subscription) = try await storedSubscription(role: .participant)
        let first = try #require(try await store.fetchPeriods(for: subscription.id).first)
        var draft = try SubscriptionSharingPeriodDraft(addingTo: subscription, after: first)
        draft.sharing.setMemberCount(4)
        draft.period.amountText = "25"
        try await store.addPeriod(draft.addInput())
        let detail = try await store.fetchDetail(for: subscription.id)
        #expect(detail.periods.map { $0.sharing?.memberCount } == [5, 4])
        #expect(detail.periods.last?.money == Money(minorUnits: 2_500, currency: .cny))
        #expect(detail.periods.last?.sharing?.purchaseMoney == nil)
        #expect(detail.periods.last?.sharing?.members.allSatisfy { $0.money == nil } == true)
        #expect(detail.subscription.money == subscription.money)
        #expect(detail.subscription.sharing == subscription.sharing)
        #expect(detail.payments.isEmpty)
    }

    @MainActor
    @Test func changingHistoricalMembersPricesAndDatesKeepsLinkedPaymentSnapshot() async throws {
        let (store, subscription) = try await storedSubscription()
        let original = try #require(try await store.fetchPeriods(for: subscription.id).first)
        try await store.addPayment(.init(
            payment: .init(
                id: UUID(), subscriptionID: subscription.id, periodRecordID: original.id,
                kind: .manual, paymentDate: .today, money: Money(minorUnits: 10_000, currency: .cny),
                periodStart: original.start, periodEnd: original.end, note: "", attachmentReferences: []
            ), expectedSubscriptionRevision: 1
        ))
        let before = try await store.fetchDetail(for: subscription.id)
        var draft = try SubscriptionSharingPeriodDraft(period: original, expectedRevision: before.subscription.revision)
        draft.sharing.setMemberCount(3)
        draft.period.amountText = "40"
        draft.period.endDate = try LocalDate(iso8601Text: "2026-10-30").date()
        try await store.updatePeriod(draft.updateInput())
        let after = try await store.fetchDetail(for: subscription.id)
        #expect(after.payments == before.payments)
        #expect(after.periods.first?.sharing?.memberCount == 3)
        #expect(after.periods.first?.money == Money(minorUnits: 4_000, currency: .cny))
        #expect(after.subscription.sharing == subscription.sharing)
        #expect(after.subscription.money == subscription.money)
    }

    @MainActor
    @Test(arguments: [false, true])
    func cancellingKeepsDetachedFieldBindingsValidAndIsolatesTheNextSession(isCreating: Bool) throws {
        let subscription = try subscription()
        let original = period(subscription: subscription)
        let state = SubscriptionSharingPeriodEditorState()
        if isCreating {
            state.beginAdding(subscription: subscription, periods: [original])
        } else {
            state.beginEditing(period: original, expectedRevision: 1)
        }
        @Bindable var session = try #require(state.editorSession)
        let amount = $session.draft.period.amountText
        let startDate = $session.draft.period.startDate
        let sharing = $session.draft.sharing
        amount.wrappedValue = "35"
        let previousStart = startDate.wrappedValue

        state.cancelEditing()

        // Native controls can still read or commit field values while their view is being removed.
        #expect(amount.wrappedValue == "35")
        #expect(startDate.wrappedValue == previousStart)
        #expect(sharing.wrappedValue.memberCount == 5)
        amount.wrappedValue = "90"
        sharing.wrappedValue.setMemberCount(3)
        #expect(state.editorSession == nil)

        state.beginEditing(period: original, expectedRevision: 2)
        let nextSession = try #require(state.editorSession)
        #expect(nextSession !== session)
        amount.wrappedValue = "91"
        startDate.wrappedValue = try LocalDate(iso8601Text: "2026-10-15").date()
        #expect(nextSession.draft.period.amountText == original.money.inputText)
        #expect(nextSession.draft.period.startDate == original.start.date())
        #expect(nextSession.draft.sharing.memberCount == 5)
        #expect(nextSession.draft.expectedRevision == 2)
        #expect(original.sharing?.memberCount == 5)
    }

    @MainActor
    @Test(arguments: [false, true])
    func savingKeepsDetachedFieldBindingsValidWithoutChangingSavedOrNewDrafts(isCreating: Bool) async throws {
        let subscription = try subscription()
        let original = period(subscription: subscription)
        let state = SubscriptionSharingPeriodEditorState()
        if isCreating {
            state.beginAdding(subscription: subscription, periods: [original])
        } else {
            state.beginEditing(period: original, expectedRevision: 1)
        }
        @Bindable var session = try #require(state.editorSession)
        let amount = $session.draft.period.amountText
        let sharing = $session.draft.sharing
        amount.wrappedValue = "35"
        let savedID = session.draft.id
        var savedMoney: Money?
        var savedPlan: SubscriptionSharingPlan?
        let saved = await state.save(
            periods: [original],
            addPeriod: {
                #expect(isCreating)
                savedMoney = $0.period.money
                savedPlan = $0.period.sharing
            },
            updatePeriod: {
                #expect(!isCreating)
                savedMoney = $0.money
                if case .replace(let plan) = $0.sharingUpdate { savedPlan = plan }
            }
        )

        #expect(saved)
        #expect(state.editorSession == nil)
        #expect(state.selection == .period(savedID))
        #expect(amount.wrappedValue == "35")
        #expect(sharing.wrappedValue.memberCount == 5)
        sharing.wrappedValue.setMemberCount(3)
        #expect(state.editorSession == nil)

        state.beginEditing(period: original, expectedRevision: 2)
        let nextSession = try #require(state.editorSession)
        amount.wrappedValue = "91"
        #expect(nextSession !== session)
        #expect(savedMoney == Money(minorUnits: 3_500, currency: .cny))
        #expect(savedPlan?.memberCount == 5)
        #expect(nextSession.draft.period.amountText == original.money.inputText)
        #expect(nextSession.draft.sharing.memberCount == 5)
    }

    @MainActor
    @Test func overlapRequiresConfirmationAndCancelledDraftDoesNotWrite() async throws {
        let subscription = try subscription()
        let original = period(subscription: subscription)
        let state = SubscriptionSharingPeriodEditorState()
        state.beginAdding(subscription: subscription, periods: [original])
        state.editorSession?.draft.period.startDate = original.start.date()
        state.editorSession?.draft.period.endDate = try #require(original.end).date()
        var additions = 0
        let saved = await state.save(
            periods: [original], addPeriod: { _ in additions += 1 },
            updatePeriod: { _ in Issue.record("新增草稿不应调用更新") }
        )
        #expect(!saved)
        #expect(state.isPresentingOverlapConfirmation)
        #expect(additions == 0)
        state.cancelEditing()
        #expect(state.editorSession == nil)
        #expect(!state.isPresentingOverlapConfirmation)
        state.beginAdding(subscription: subscription, periods: [original])
        state.editorSession?.draft.period.startDate = original.start.date()
        let confirmed = await state.save(
            periods: [original], confirmingOverlap: true,
            addPeriod: { _ in additions += 1 }, updatePeriod: { _ in }
        )
        #expect(confirmed)
        #expect(additions == 1)
        #expect(state.editorSession == nil)
    }

    @MainActor
    @Test func conflictPreservesDraftAndItsOriginalRevisionAfterARefresh() async throws {
        let subscription = try subscription()
        let original = period(subscription: subscription)
        let state = SubscriptionSharingPeriodEditorState()
        state.beginEditing(period: original, expectedRevision: 1)
        state.editorSession?.draft.sharing.setMemberCount(4)
        state.editorSession?.draft.period.amountText = "35"
        let failed = await state.save(
            periods: [original], addPeriod: { _ in },
            updatePeriod: { _ in throw SubscriptionStore.StoreError.revisionConflict }
        )
        #expect(!failed)
        #expect(state.error != nil)
        #expect(state.editorSession?.draft.sharing.memberCount == 4)
        #expect(state.editorSession?.draft.period.amountText == "35")
        #expect(state.editorSession?.draft.expectedRevision == 1)
        #expect(!state.isSaving)
        state.reconcileSelection(subscription: subscription, periods: [])
        #expect(state.editorSession?.draft.expectedRevision == 1)
        state.cancelEditing()
        #expect(state.editorSession == nil)
        #expect(state.error == nil)
    }

    @MainActor
    @Test func savingPreventsDuplicateSubmissionAndCancelUntilReloadCompletes() async throws {
        let subscription = try subscription()
        let state = SubscriptionSharingPeriodEditorState()
        state.beginAdding(subscription: subscription, periods: [])
        let (started, signal) = AsyncStream<Void>.makeStream()
        var continuation: CheckedContinuation<Void, Never>?
        var writes = 0
        let saving = Task { @MainActor in
            await state.save(
                periods: [], addPeriod: { _ in writes += 1 }, updatePeriod: { _ in },
                onSaved: {
                    await withCheckedContinuation {
                        continuation = $0
                        signal.yield(())
                    }
                }
            )
        }
        for await _ in started { break }
        #expect(state.isSaving)
        state.cancelEditing()
        #expect(state.editorSession != nil)
        let second = await state.save(
            periods: [], addPeriod: { _ in writes += 1 }, updatePeriod: { _ in }
        )
        #expect(!second)
        #expect(writes == 1)
        continuation?.resume()
        signal.finish()
        #expect(await saving.value)
        #expect(!state.isSaving)
        #expect(state.editorSession == nil)
    }

    private func subscription(
        id: UUID = UUID(),
        start: String? = "2026-10-01", end: String? = "2026-10-31",
        cycleMonths: Int? = 1,
        role: SubscriptionSharingRole = .organizer,
        isSharingEnabled: Bool = true
    ) throws -> SubscriptionDTO {
        let sharing = isSharingEnabled ? SubscriptionSharingPlan(
            role: role,
            purchaseMoney: role == .organizer ? Money(minorUnits: 10_000, currency: .cny) : nil,
            members: (2...5).map {
                .init(id: UUID(), name: "Member \($0)", money: role == .organizer
                    ? Money(minorUnits: 2_000, currency: .cny) : nil)
            }
        ) : nil
        return SubscriptionDTO(
            id: id, name: "Shared", symbolName: "person.2",
            iconResourceName: nil, iconURLString: nil, category: .media,
            managementState: .active, billingKind: .recurring,
            periodStart: try start.map { try LocalDate(iso8601Text: $0) },
            expiry: try end.map { try LocalDate(iso8601Text: $0) },
            cycleMonths: cycleMonths,
            money: Money(minorUnits: 2_000, currency: .cny),
            sharing: sharing,
            note: "", reminderEnabled: true, revision: 1, createdAt: Date(), updatedAt: Date()
        )
    }

    private func period(subscription: SubscriptionDTO, cycleMonths: Int? = 1) -> SubscriptionPeriodDTO {
        SubscriptionPeriodDTO(
            id: UUID(), subscriptionID: subscription.id, billingKind: .recurring,
            cycleMonths: cycleMonths, start: subscription.periodStart ?? .today,
            end: subscription.expiry, money: subscription.money, sharing: subscription.sharing,
            createdAt: Date()
        )
    }

    private func period(input: SubscriptionPeriodCreateInput) -> SubscriptionPeriodDTO {
        SubscriptionPeriodDTO(
            id: input.id, subscriptionID: input.subscriptionID, billingKind: input.billingKind,
            cycleMonths: input.cycleMonths, start: input.start, end: input.end,
            money: input.money, sharing: input.sharing, createdAt: Date()
        )
    }

    @MainActor
    private func storedSubscription(
        role: SubscriptionSharingRole = .organizer
    ) async throws -> (SubscriptionStore, SubscriptionDTO) {
        let container = try PersistenceController().makeContainer(
            schema: Schema(versionedSchema: AppSchemaV6.self), inMemory: true
        )
        let store = SubscriptionStore(modelContainer: container)
        let source = try subscription(role: role)
        _ = try await store.create(SubscriptionCreateInput(
            id: source.id, name: source.name, symbolName: source.symbolName,
            iconResourceName: nil, iconURLString: nil, category: source.category,
            managementState: source.managementState, billingKind: source.billingKind,
            periodStart: source.periodStart, expiry: source.expiry, cycleMonths: source.cycleMonths,
            money: source.money, sharing: source.sharing, note: source.note, reminderEnabled: true
        ))
        let detail = try await store.fetchDetail(for: source.id)
        return (store, detail.subscription)
    }
}
