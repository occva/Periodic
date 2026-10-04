import Foundation
import SwiftData
import Testing
@testable import Periodic

@MainActor
struct SubscriptionPaymentTests {
    @Test func editingPaymentPreservesIndependentAmountAndCoverageSnapshot() throws {
        let subscriptionID = UUID()
        let periodID = UUID()
        let originalStart = LocalDate(dayNumber: 20_000)
        let originalEnd = LocalDate(dayNumber: 20_029)
        let original = SubscriptionPaymentDTO(
            id: UUID(),
            subscriptionID: subscriptionID,
            periodRecordID: periodID,
            kind: .renewal,
            paymentDate: originalStart,
            money: Money(minorUnits: 1_499, currency: .usd),
            periodStart: originalStart,
            periodEnd: originalEnd,
            note: "",
            attachmentReferences: [],
            revision: 1,
            createdAt: .now,
            updatedAt: .now
        )
        let changedPeriod = SubscriptionPeriodDTO(
            id: periodID,
            subscriptionID: subscriptionID,
            billingKind: .recurring,
            cycleMonths: 1,
            start: LocalDate(dayNumber: 21_000),
            end: LocalDate(dayNumber: 21_029),
            money: Money(minorUnits: 9_999, currency: .usd),
            createdAt: .now
        )
        var draft = SubscriptionPaymentDraft(payment: original)
        draft.amountText = "12.34"
        draft.note = "只修改实际支付和备注"

        var input = try draft.updateInput(
            expectedSubscriptionRevision: 2,
            periods: [changedPeriod]
        )
        #expect(input.money == Money(minorUnits: 1_234, currency: .usd))
        #expect(input.money != changedPeriod.money)
        #expect(input.periodStart == originalStart)
        #expect(input.periodEnd == originalEnd)

        let replacementPeriod = SubscriptionPeriodDTO(
            id: UUID(),
            subscriptionID: subscriptionID,
            billingKind: .recurring,
            cycleMonths: 3,
            start: LocalDate(dayNumber: 22_000),
            end: LocalDate(dayNumber: 22_089),
            money: Money(minorUnits: 8_888, currency: .usd),
            createdAt: .now
        )
        draft.periodRecordID = replacementPeriod.id
        input = try draft.updateInput(
            expectedSubscriptionRevision: 2,
            periods: [changedPeriod, replacementPeriod]
        )
        #expect(input.money == Money(minorUnits: 1_234, currency: .usd))
        #expect(input.money != replacementPeriod.money)
        #expect(input.periodStart == replacementPeriod.start)
        #expect(input.periodEnd == replacementPeriod.end)

        draft.periodRecordID = nil
        input = try draft.updateInput(
            expectedSubscriptionRevision: 2,
            periods: [changedPeriod]
        )
        #expect(input.periodRecordID == nil)
        #expect(input.periodStart == originalStart)
        #expect(input.periodEnd == originalEnd)
    }

    @Test func renewalPaymentRequiresCompleteCoverageSnapshot() async throws {
        let store = try makeStore()
        let input = try makeSubscriptionInput()
        _ = try await store.create(input)
        let subscription = try #require(try await store.fetchAll().first)

        await #expect(throws: SubscriptionStore.StoreError.self) {
            try await store.addPayment(
                SubscriptionPaymentAddInput(
                    payment: SubscriptionPaymentCreateInput(
                        id: UUID(),
                        subscriptionID: subscription.id,
                        periodRecordID: nil,
                        kind: .renewal,
                        paymentDate: .today,
                        money: Money(minorUnits: 777, currency: .cny),
                        periodStart: nil,
                        periodEnd: nil,
                        note: "",
                        attachmentReferences: []
                    ),
                    expectedSubscriptionRevision: subscription.revision
                )
            )
        }
        #expect(try await store.fetchPayments(for: subscription.id).isEmpty)
    }

    @Test func detailSnapshotReturnsLatestSubscriptionPeriodsAndPaymentsTogether() async throws {
        let store = try makeStore()
        let input = try makeSubscriptionInput()
        _ = try await store.create(input)
        let subscription = try #require(try await store.fetchAll().first)
        try await store.addPayment(
            SubscriptionPaymentAddInput(
                payment: SubscriptionPaymentCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    periodRecordID: nil,
                    kind: .manual,
                    paymentDate: .today,
                    money: Money(minorUnits: 345, currency: .usd),
                    periodStart: nil,
                    periodEnd: nil,
                    note: "独立实际支付",
                    attachmentReferences: []
                ),
                expectedSubscriptionRevision: subscription.revision
            )
        )

        let snapshot = try await store.fetchDetail(for: subscription.id)

        #expect(snapshot.subscription.revision == subscription.revision + 1)
        #expect(snapshot.periods.count == 1)
        #expect(snapshot.payments.map(\.money) == [Money(minorUnits: 345, currency: .usd)])
        #expect(snapshot.subscription.money == input.money)
    }

    @Test func paymentScreenshotsCanBeAddedDeduplicatedAndRemovedInOrder() async throws {
        let store = try makeStore()
        let input = try makeSubscriptionInput()
        _ = try await store.create(input)
        var subscription = try #require(try await store.fetchAll().first)
        let firstReference = PaymentAttachmentReference.make(
            contentHash: String(repeating: "a", count: 64)
        )
        let secondReference = PaymentAttachmentReference.make(
            contentHash: String(repeating: "b", count: 64)
        )
        let thirdReference = PaymentAttachmentReference.make(
            contentHash: String(repeating: "c", count: 64)
        )

        try await store.addPayment(
            SubscriptionPaymentAddInput(
                payment: SubscriptionPaymentCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    periodRecordID: nil,
                    kind: .manual,
                    paymentDate: .today,
                    money: input.money,
                    periodStart: nil,
                    periodEnd: nil,
                    note: "含截图",
                    attachmentReferences: [firstReference, secondReference, firstReference]
                ),
                expectedSubscriptionRevision: subscription.revision
            )
        )
        subscription = try #require(try await store.fetchAll().first)
        var payment = try #require(try await store.fetchPayments(for: subscription.id).first)
        #expect(payment.attachmentReferences == [firstReference, secondReference])

        try await store.updatePayment(
            SubscriptionPaymentUpdateInput(
                original: payment,
                expectedSubscriptionRevision: subscription.revision,
                periodRecordID: nil,
                paymentDate: payment.paymentDate,
                money: payment.money,
                periodStart: nil,
                periodEnd: nil,
                note: payment.note,
                attachmentReferences: [secondReference, thirdReference]
            )
        )
        subscription = try #require(try await store.fetchAll().first)
        payment = try #require(try await store.fetchPayments(for: subscription.id).first)
        #expect(payment.attachmentReferences == [secondReference, thirdReference])
        #expect(
            try await store.referencedPaymentAttachmentReferences()
                == Set([secondReference, thirdReference])
        )

        try await store.updatePayment(
            SubscriptionPaymentUpdateInput(
                original: payment,
                expectedSubscriptionRevision: subscription.revision,
                periodRecordID: nil,
                paymentDate: payment.paymentDate,
                money: payment.money,
                periodStart: nil,
                periodEnd: nil,
                note: payment.note,
                attachmentReferences: []
            )
        )
        #expect(
            try await store.fetchPayments(for: subscription.id).first?
                .attachmentReferences == []
        )
        #expect(try await store.referencedPaymentAttachmentReferences().isEmpty)
    }

    @Test func paymentCanBeAddedEditedAndDeletedWithoutChangingCurrentPrice() async throws {
        let store = try makeStore()
        let input = try makeSubscriptionInput()
        _ = try await store.create(input)
        var subscription = try #require(try await store.fetchAll().first)
        let period = try #require(try await store.fetchPeriods(for: subscription.id).first)

        try await store.addPayment(
            SubscriptionPaymentAddInput(
                payment: SubscriptionPaymentCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    periodRecordID: period.id,
                    kind: .manual,
                    paymentDate: period.start,
                    money: Money(minorUnits: 990, currency: .cny),
                    periodStart: period.start,
                    periodEnd: period.end,
                    note: "优惠消费",
                    attachmentReferences: []
                ),
                expectedSubscriptionRevision: subscription.revision
            )
        )

        subscription = try #require(try await store.fetchAll().first)
        let added = try #require(try await store.fetchPayments(for: subscription.id).first)
        #expect(added.money == Money(minorUnits: 990, currency: .cny))
        #expect(subscription.money == input.money)

        try await store.updatePayment(
            SubscriptionPaymentUpdateInput(
                original: added,
                expectedSubscriptionRevision: subscription.revision,
                periodRecordID: nil,
                paymentDate: added.paymentDate,
                money: Money(minorUnits: 880, currency: .cny),
                periodStart: nil,
                periodEnd: nil,
                note: "纠正金额",
                attachmentReferences: []
            )
        )

        subscription = try #require(try await store.fetchAll().first)
        let updated = try #require(try await store.fetchPayments(for: subscription.id).first)
        #expect(updated.periodRecordID == nil)
        #expect(updated.money == Money(minorUnits: 880, currency: .cny))
        #expect(updated.note == "纠正金额")
        #expect(subscription.money == input.money)

        try await store.deletePayment(
            SubscriptionPaymentDeleteInput(
                original: updated,
                expectedSubscriptionRevision: subscription.revision
            )
        )
        #expect(try await store.fetchPayments(for: subscription.id).isEmpty)
    }

    @Test func sharedScreenshotRemainsReferencedUntilLastPaymentIsDeleted() async throws {
        let store = try makeStore()
        let input = try makeSubscriptionInput()
        _ = try await store.create(input)
        var subscription = try #require(try await store.fetchAll().first)
        let sharedReference = PaymentAttachmentReference.make(
            contentHash: String(repeating: "d", count: 64)
        )

        for note in ["First", "Second"] {
            try await store.addPayment(
                SubscriptionPaymentAddInput(
                    payment: SubscriptionPaymentCreateInput(
                        id: UUID(),
                        subscriptionID: subscription.id,
                        periodRecordID: nil,
                        kind: .manual,
                        paymentDate: .today,
                        money: input.money,
                        periodStart: nil,
                        periodEnd: nil,
                        note: note,
                        attachmentReferences: [sharedReference]
                    ),
                    expectedSubscriptionRevision: subscription.revision
                )
            )
            subscription = try #require(try await store.fetchAll().first)
        }

        var payments = try await store.fetchPayments(for: subscription.id)
        try await store.deletePayment(
            SubscriptionPaymentDeleteInput(
                original: payments.removeFirst(),
                expectedSubscriptionRevision: subscription.revision
            )
        )
        #expect(
            try await store.referencedPaymentAttachmentReferences()
                == Set([sharedReference])
        )

        subscription = try #require(try await store.fetchAll().first)
        let remainingPayment = try #require(
            try await store.fetchPayments(for: subscription.id).first
        )
        try await store.deletePayment(
            SubscriptionPaymentDeleteInput(
                original: remainingPayment,
                expectedSubscriptionRevision: subscription.revision
            )
        )
        #expect(try await store.referencedPaymentAttachmentReferences().isEmpty)
    }

    @Test func deletingPeriodUnlinksPaymentButKeepsItsSnapshot() async throws {
        let store = try makeStore()
        let input = try makeSubscriptionInput()
        _ = try await store.create(input)
        var subscription = try #require(try await store.fetchAll().first)
        let period = try #require(try await store.fetchPeriods(for: subscription.id).first)
        try await store.addPayment(
            SubscriptionPaymentAddInput(
                payment: SubscriptionPaymentCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    periodRecordID: period.id,
                    kind: .initial,
                    paymentDate: period.start,
                    money: input.money,
                    periodStart: period.start,
                    periodEnd: period.end,
                    note: "",
                    attachmentReferences: []
                ),
                expectedSubscriptionRevision: subscription.revision
            )
        )

        subscription = try #require(try await store.fetchAll().first)
        try await store.deletePeriod(
            SubscriptionPeriodDeleteInput(
                original: period,
                expectedSubscriptionRevision: subscription.revision
            )
        )

        let payment = try #require(try await store.fetchPayments(for: subscription.id).first)
        #expect(payment.periodRecordID == nil)
        #expect(payment.periodStart == period.start)
        #expect(payment.periodEnd == period.end)
        #expect(payment.money == input.money)
    }

    @Test func futurePaymentAndForeignPeriodAreRejectedAtomically() async throws {
        let store = try makeStore()
        let first = try makeSubscriptionInput(name: "First")
        let second = try makeSubscriptionInput(name: "Second")
        _ = try await store.create(first)
        _ = try await store.create(second)
        let subscriptions = try await store.fetchAll()
        let firstSubscription = try #require(subscriptions.first { $0.id == first.id })
        let foreignPeriod = try #require(
            try await store.fetchPeriods(for: second.id).first
        )

        await #expect(throws: SubscriptionStore.StoreError.self) {
            try await store.addPayment(
                SubscriptionPaymentAddInput(
                    payment: SubscriptionPaymentCreateInput(
                        id: UUID(),
                        subscriptionID: first.id,
                        periodRecordID: foreignPeriod.id,
                        kind: .manual,
                        paymentDate: try #require(LocalDate.today.addingDays(1)),
                        money: first.money,
                        periodStart: nil,
                        periodEnd: nil,
                        note: "",
                        attachmentReferences: []
                    ),
                    expectedSubscriptionRevision: firstSubscription.revision
                )
            )
        }
        #expect(try await store.fetchPayments(for: first.id).isEmpty)

        await #expect(throws: SubscriptionStore.StoreError.self) {
            try await store.addPayment(
                SubscriptionPaymentAddInput(
                    payment: SubscriptionPaymentCreateInput(
                        id: UUID(),
                        subscriptionID: first.id,
                        periodRecordID: foreignPeriod.id,
                        kind: .manual,
                        paymentDate: .today,
                        money: first.money,
                        periodStart: foreignPeriod.start,
                        periodEnd: foreignPeriod.end,
                        note: "",
                        attachmentReferences: []
                    ),
                    expectedSubscriptionRevision: firstSubscription.revision
                )
            )
        }
        #expect(try await store.fetchPayments(for: first.id).isEmpty)
    }

    @Test func deletingSubscriptionIncludesAndRemovesPayments() async throws {
        let store = try makeStore()
        let input = try makeSubscriptionInput()
        _ = try await store.create(input)
        var subscription = try #require(try await store.fetchAll().first)
        try await store.addPayment(
            SubscriptionPaymentAddInput(
                payment: SubscriptionPaymentCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    periodRecordID: nil,
                    kind: .manual,
                    paymentDate: .today,
                    money: input.money,
                    periodStart: nil,
                    periodEnd: nil,
                    note: "",
                    attachmentReferences: []
                ),
                expectedSubscriptionRevision: subscription.revision
            )
        )
        subscription = try #require(try await store.fetchAll().first)

        let preview = try await store.previewDeletion([
            SubscriptionMutationTarget(
                id: subscription.id,
                expectedRevision: subscription.revision
            )
        ])
        #expect(preview.paymentCount == 1)
        let result = try await store.delete(preview)
        #expect(result.deletedPaymentCount == 1)
        #expect(try await store.fetchPayments(for: subscription.id).isEmpty)
    }

    private func makeStore() throws -> SubscriptionStore {
        let container = try PersistenceController().makeContainer(
            schema: Schema([
                SubscriptionSharingRecord.self,
                SubscriptionRecord.self,
                SubscriptionPeriodRecord.self,
                SubscriptionPaymentRecord.self,
                SubscriptionPaymentAttachmentRecord.self,
                SubscriptionPaymentAttachmentItemRecord.self,
            ]),
            inMemory: true
        )
        return SubscriptionStore(modelContainer: container)
    }

    private func makeSubscriptionInput(
        name: String = "Payment Test"
    ) throws -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: UUID(),
            name: name,
            symbolName: "creditcard",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: try LocalDate(iso8601Text: "2026-01-01"),
            expiry: try LocalDate(iso8601Text: "2026-12-31"),
            cycleMonths: 12,
            money: Money(minorUnits: 1_200, currency: .cny),
            note: "",
            reminderEnabled: true
        )
    }
}
