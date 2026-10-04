import Foundation
import SwiftData
import Testing
@testable import Periodic

struct SubscriptionSharingTests {
    @Test func unequalQuotesKeepPersonalForecastAndPurchasePriceSeparate() throws {
        let plan = organizer()
        let mine = price(6_000)
        try plan.validate(myMoney: mine)
        #expect(plan.memberCount == 4)
        #expect(try plan.quotedTotal(myMoney: mine) == price(30_000))
        #expect(plan.defaultPaymentMoney(myMoney: mine) == price(30_000))
        #expect(mine.monthlyAmount(cycleMonths: 12) == 5)
    }

    @Test func unknownMemberIsDifferentFromFreeMember() throws {
        let unknown = participant(amount: nil)
        let free = participant(amount: price(0))
        try unknown.validate(myMoney: price(0))
        #expect(try unknown.quotedTotal(myMoney: price(0)) == nil)
        #expect(try free.quotedTotal(myMoney: price(0)) == price(0))
        #expect(unknown.defaultPaymentMoney(myMoney: price(500)) == price(500))
    }

    @Test func memberIdentityCurrencyAndOrganizerPriceAreValidated() {
        let memberID = UUID()
        let plans = [
            SubscriptionSharingPlan(role: .participant, purchaseMoney: nil, members: []),
            SubscriptionSharingPlan(role: .organizer, purchaseMoney: nil, members: [member()]),
            SubscriptionSharingPlan(role: .participant, purchaseMoney: nil, members: [
                member(id: memberID), member(id: memberID),
            ]),
            SubscriptionSharingPlan(role: .participant, purchaseMoney: nil, members: [member(name: " \n")]),
            participant(amount: Money(minorUnits: 500, currency: .usd)),
            participant(amount: price(-1)),
        ]
        for plan in plans {
            #expect(throws: (any Error).self) { try plan.validate(myMoney: price(500)) }
        }
    }

    @Test func aggregateOverflowIsRejectedIncludingPartialQuotes() {
        for plan in [
            participant(amount: price(Int64.max)),
            SubscriptionSharingPlan(role: .participant, purchaseMoney: nil, members: [
                member(money: nil), member(money: price(Int64.max)),
            ]),
        ] {
            #expect(throws: Money.ValidationError.overflow) { try plan.validate(myMoney: price(1)) }
        }
    }

    @Test func draftHonorsPrecisionUnknownValuesAndCancelIsolation() throws {
        let original = organizer()
        var draft = SubscriptionSharingDraft(plan: original)
        for member in original.members.dropFirst() {
            draft.removeMember(id: member.id)
        }
        draft.members[0].amountText = "0"
        #expect(original.memberCount == 4)
        let saved = try #require(try draft.plan(myMoney: price(6_000)))
        #expect(saved.memberCount == 2)
        #expect(saved.members.first?.money == price(0))
        draft.members[0].amountText = "1.234"
        #expect(throws: Money.ValidationError.precision(2)) { try draft.plan(myMoney: price(6_000)) }
        draft.purchaseAmountText = "300"
        draft.members[0].amountText = "1.1"
        #expect(throws: Money.ValidationError.precision(0)) {
            try draft.plan(myMoney: Money(minorUnits: 60, currency: .jpy))
        }
        draft.isEnabled = false
        #expect(try draft.plan(myMoney: price(6_000)) == nil)
    }

    @Test func copyingCreatesNewMemberIdentitiesAndProrationPreservesUnknowns() throws {
        let plan = organizer()
        let copy = plan.copyingMembers()
        #expect(Set(copy.members.map(\.id)).isDisjoint(with: plan.members.map(\.id)))
        #expect(copy.members.map(\.money) == plan.members.map(\.money))
        let monthly = try plan.prorated(from: 12, to: 1)
        #expect(monthly.purchaseMoney == price(2_500))
        #expect(monthly.members.map(\.money) == [price(583), price(667), price(750)])
        #expect(try participant(amount: nil).prorated(from: 12, to: 1).members.first?.money == nil)
    }

    @Test func threeDecimalCurrencyQuotesRemainExact() throws {
        var draft = SubscriptionSharingDraft()
        draft.isEnabled = true
        draft.members[0].amountText = "0.001"
        let mine = Money(minorUnits: 1, currency: .kwd)
        let plan = try #require(try draft.plan(myMoney: mine))
        #expect(try plan.quotedTotal(myMoney: mine) == Money(minorUnits: 2, currency: .kwd))
    }

    @MainActor
    @Test func sharedCreationForecastsOnlyMyPriceAndCapturesInitialPeriod() async throws {
        let container = try makeContainer()
        let store = SubscriptionStore(modelContainer: container)
        let input = makeInput(sharing: organizer())
        _ = try await store.create(input)
        let detail = try await store.fetchDetail(for: input.id)
        #expect(detail.subscription.sharing == input.sharing)
        #expect(detail.periods.first?.sharing == input.sharing)
        #expect(detail.payments.isEmpty)
        let forecast = MenuBarSnapshotBuilder.makeSnapshot(
            subscriptions: [detail.subscription], referenceDate: .today
        ).currencyForecasts
        #expect(forecast.first?.monthly == 5)
        #expect(forecast.first?.annual == 60)
        #expect(forecast.first?.itemCount == 1)
    }

    @MainActor
    @Test func currentEditsAndDisablingSharingPreserveHistoryAndRejectStaleWrites() async throws {
        let container = try makeContainer()
        let store = SubscriptionStore(modelContainer: container)
        let original = makeInput(sharing: organizer())
        _ = try await store.create(original)
        let changed = makeInput(id: original.id, money: price(8_000), sharing: participant(amount: nil))
        try await store.update(changed, expectedRevision: 1, historyPolicy: .currentOnly)
        await #expect(throws: SubscriptionStore.StoreError.revisionConflict) {
            try await store.update(original, expectedRevision: 1, historyPolicy: .currentOnly)
        }
        var detail = try await store.fetchDetail(for: original.id)
        #expect(detail.subscription.money == price(8_000))
        #expect(detail.subscription.sharing == changed.sharing)
        #expect(detail.subscription.revision == 2)
        #expect(detail.periods.first?.sharing == original.sharing)
        #expect(detail.periods.first?.money == original.money)
        try await store.update(
            makeInput(id: original.id, sharing: nil), expectedRevision: 2, historyPolicy: .currentOnly
        )
        detail = try await store.fetchDetail(for: original.id)
        #expect(detail.subscription.sharing == nil)
        #expect(detail.periods.first?.sharing == original.sharing)
    }

    @MainActor
    @Test func invalidBatchRollsBackSubscriptionsPeriodsAndSharing() async throws {
        let container = try makeContainer()
        let store = SubscriptionStore(modelContainer: container)
        let invalid = makeInput(sharing: .init(role: .organizer, purchaseMoney: nil, members: [member()]))
        await #expect(throws: SubscriptionSharingError.self) {
            try await store.create([makeInput(sharing: organizer()), invalid])
        }
        #expect(try await store.fetchAll().isEmpty)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<SubscriptionPeriodRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SubscriptionSharingRecord>()) == 0)
    }

    @MainActor
    @Test func editingAndDeletingHistoricalPeriodPreservesTheCurrentPlan() async throws {
        let container = try makeContainer()
        let store = SubscriptionStore(modelContainer: container)
        let input = makeInput(sharing: organizer())
        _ = try await store.create(input)
        let oldPeriod = try #require(try await store.fetchPeriods(for: input.id).first)
        let current = participant(amount: nil)
        try await store.update(makeInput(id: input.id, sharing: current), expectedRevision: 1, historyPolicy: .currentOnly)
        try await store.updatePeriod(.init(
            original: oldPeriod, expectedSubscriptionRevision: 2, billingKind: .recurring,
            cycleMonths: 12, start: oldPeriod.start, end: oldPeriod.end, money: price(6_001)
        ))
        let edited = try #require(try await store.fetchPeriods(for: input.id).first)
        #expect(edited.sharing == input.sharing)
        await #expect(throws: SubscriptionSharingError.self) {
            try await store.updatePeriod(.init(
                original: edited, expectedSubscriptionRevision: 3, billingKind: .recurring,
                cycleMonths: 12, start: edited.start, end: edited.end,
                money: Money(minorUnits: 1, currency: .usd)
            ))
        }
        try await store.deletePeriod(.init(original: edited, expectedSubscriptionRevision: 3))
        let detail = try await store.fetchDetail(for: input.id)
        #expect(detail.subscription.sharing == current)
        #expect(detail.subscription.money == input.money)
        #expect(detail.periods.isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SubscriptionSharingRecord>()) == 1)
    }

    @MainActor
    @Test func renewalRecordsGrossPaymentPersonalQuoteAndSnapshotOnce() async throws {
        let container = try makeContainer()
        let store = SubscriptionStore(modelContainer: container)
        let input = makeInput(sharing: organizer())
        _ = try await store.create(input)
        let subscription = try #require(try await store.fetchAll().first)
        let preview = try SubscriptionRenewalRule.preview(subscription: subscription, referenceDate: .today)
        #expect(preview.defaultPaymentMoney == price(30_000))
        let request = SubscriptionRenewalRequest(
            subscriptionID: input.id, expectedRevision: 1, expectedExpiry: .today,
            cycleMonths: 12, quotedMoney: input.money, paymentDate: .today,
            paymentMoney: price(28_000), paymentNote: ""
        )
        _ = try await store.confirmAutomaticRenewal(request)
        await #expect(throws: SubscriptionStore.StoreError.revisionConflict) {
            try await store.confirmAutomaticRenewal(request)
        }
        let detail = try await store.fetchDetail(for: input.id)
        #expect(detail.periods.count == 2)
        #expect(detail.periods.allSatisfy { $0.money == input.money && $0.sharing == input.sharing })
        #expect(detail.payments.count == 1)
        #expect(detail.payments.first?.money == price(28_000))
        #expect(detail.subscription.money == input.money)
        #expect(detail.subscription.sharing == input.sharing)
        #expect(detail.subscription.revision == 2)
    }

    @MainActor
    @Test func failedRenewalRollsBackTheNewSharingSnapshot() async throws {
        let container = try makeContainer()
        let store = SubscriptionStore(modelContainer: container)
        let input = makeInput(sharing: organizer())
        _ = try await store.create(input)
        let tomorrow = try #require(LocalDate.today.addingDays(1))
        let request = SubscriptionRenewalRequest(
            subscriptionID: input.id, expectedRevision: 1, expectedExpiry: .today,
            cycleMonths: 12, quotedMoney: input.money, paymentDate: tomorrow,
            paymentMoney: price(30_000), paymentNote: ""
        )
        await #expect(throws: SubscriptionStore.StoreError.invalidPaymentDate) {
            try await store.confirmAutomaticRenewal(request)
        }
        let detail = try await store.fetchDetail(for: input.id)
        #expect(detail.periods.count == 1)
        #expect(detail.payments.isEmpty)
        #expect(detail.subscription.revision == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SubscriptionSharingRecord>()) == 2)
    }

    @MainActor
    @Test func deletionCleansCurrentAndHistoricalPlansAndLifetimeNeverForecasts() async throws {
        let container = try makeContainer()
        let store = SubscriptionStore(modelContainer: container)
        let input = makeInput(sharing: organizer(), billingKind: .lifetime)
        _ = try await store.create(input)
        let subscription = try #require(try await store.fetchAll().first)
        #expect(MenuBarSnapshotBuilder.makeSnapshot(
            subscriptions: [subscription], referenceDate: .today
        ).currencyForecasts.isEmpty)
        let preview = try await store.previewDeletion([
            .init(id: input.id, expectedRevision: subscription.revision),
        ])
        _ = try await store.delete(preview)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SubscriptionSharingRecord>()) == 0)
    }

    @MainActor
    @Test func backupRoundTripsBothPlansAndDetectsSharingConflicts() async throws {
        let source = try makeContainer()
        let subscriptionStore = SubscriptionStore(modelContainer: source)
        let input = makeInput(sharing: organizer())
        _ = try await subscriptionStore.create(input)
        try await subscriptionStore.update(
            makeInput(id: input.id, sharing: participant(amount: nil)),
            expectedRevision: 1, historyPolicy: .currentOnly
        )
        let snapshot = try await DataExchangeStore(modelContainer: source).snapshot()
        let encoded = try DataPackageCodec.encode(snapshot: snapshot, assets: [:])
        let decoded = try DataPackageCodec.decode(fileWrapper: DataPackageCodec.fileWrapper(for: encoded))
        #expect(decoded.manifest.formatVersion == 5)
        #expect(decoded.manifest.minimumReaderVersion == 5)
        #expect(decoded.snapshot == snapshot)
        let destination = try makeContainer()
        let exchange = DataExchangeStore(modelContainer: destination)
        _ = try await exchange.execute(
            imported: decoded.snapshot, expectedDigest: exchange.digest(), conflictResolution: .useImported
        )
        let detail = try await SubscriptionStore(modelContainer: destination).fetchDetail(for: input.id)
        #expect(detail.subscription.sharing == snapshot.subscriptions.first?.sharing)
        #expect(detail.periods.first?.sharing == input.sharing)
        let repeated = try await exchange.execute(
            imported: decoded.snapshot, expectedDigest: exchange.digest(), conflictResolution: .useImported
        )
        #expect(repeated.added == 0 && repeated.updated == 0)
        var changed = decoded.snapshot
        changed.subscriptions[0].sharing = organizer()
        #expect(try await exchange.preview(imported: changed).subscriptions.conflicts == 1)
        let before = try await exchange.digest()
        _ = try await exchange.execute(imported: changed, expectedDigest: before, conflictResolution: .keepLocal)
        #expect(try await exchange.digest() == before)
        _ = try await exchange.execute(imported: changed, expectedDigest: before, conflictResolution: .useImported)
        let imported = try await SubscriptionStore(modelContainer: destination).fetchDetail(for: input.id)
        #expect(imported.subscription.sharing == changed.subscriptions[0].sharing)
        #expect(imported.periods.first?.sharing == input.sharing)
        #expect(imported.subscription.revision == 2)
        changed.subscriptions[0].sharing = participant(amount: Money(minorUnits: 1, currency: .usd))
        #expect(throws: SubscriptionSharingError.self) { try DataPackageCodec.encode(snapshot: changed, assets: [:]) }
    }

    @MainActor
    @Test func versionFiveStoreMigratesWithoutFabricatingSharingOrPayments() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Periodic.store")
        let input = makeInput(sharing: nil)
        do {
            let container = try PersistenceController(storeURL: url).makeContainer(
                schema: Schema(versionedSchema: AppSchemaV5.self)
            )
            let context = ModelContext(container)
            context.insert(SubscriptionRecord(input: input))
            try context.save()
        }
        let container = try PersistenceController(storeURL: url).makeContainer(
            schema: Schema(versionedSchema: AppSchemaV6.self), migrationPlan: AppSchemaMigrationPlan.self
        )
        let detail = try await SubscriptionStore(modelContainer: container).fetchDetail(for: input.id)
        #expect(detail.subscription.money == input.money)
        #expect(detail.subscription.sharing == nil)
        #expect(detail.subscription.revision == 1)
        #expect(detail.periods.isEmpty && detail.payments.isEmpty)
    }

    @MainActor
    @Test func sharedCurrentAndHistoricalPlansSurviveDiskReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Periodic.store")
        let input = makeInput(sharing: organizer())
        do {
            let container = try PersistenceController(storeURL: url).makeContainer(
                schema: Schema(versionedSchema: AppSchemaV6.self), migrationPlan: AppSchemaMigrationPlan.self
            )
            _ = try await SubscriptionStore(modelContainer: container).create(input)
        }
        let reopened = try PersistenceController(storeURL: url).makeContainer(
            schema: Schema(versionedSchema: AppSchemaV6.self), migrationPlan: AppSchemaMigrationPlan.self
        )
        let detail = try await SubscriptionStore(modelContainer: reopened).fetchDetail(for: input.id)
        #expect(detail.subscription.sharing == input.sharing)
        #expect(detail.periods.first?.sharing == input.sharing)
        #expect(detail.payments.isEmpty)
    }

    @MainActor
    @Test func legacyPackageLoadsOrdinarySubscriptionsAndCannotHideSharing() async throws {
        let container = try makeContainer()
        _ = try await SubscriptionStore(modelContainer: container).create(makeInput(sharing: nil))
        let snapshot = try await DataExchangeStore(modelContainer: container).snapshot()
        let ordinary = try DataPackageCodec.encode(snapshot: snapshot, assets: [:])
        let old = try downgrade(ordinary, to: 4)
        let decoded = try DataPackageCodec.decode(fileWrapper: old)
        #expect(decoded.manifest.formatVersion == 4)
        #expect(decoded.snapshot.subscriptions.first?.sharing == nil)
        var shared = snapshot
        shared.subscriptions[0].sharing = organizer()
        let package = try DataPackageCodec.encode(snapshot: shared, assets: [:])
        let disguised = try downgrade(package, to: 4)
        #expect(throws: DataExchangeError.self) { try DataPackageCodec.decode(fileWrapper: disguised) }
    }

    private func downgrade(_ package: EncodedDataPackage, to version: Int) throws -> FileWrapper {
        var files = package.files
        let data = try #require(files["manifest.json"])
        var manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        manifest["formatVersion"] = version
        manifest["minimumReaderVersion"] = version
        files["manifest.json"] = try JSONSerialization.data(withJSONObject: manifest)
        files["checksums.json"] = try JSONEncoder().encode(Dictionary(
            uniqueKeysWithValues: files.filter { $0.key != "checksums.json" }.map { ($0.key, DataPackageCodec.sha256($0.value)) }
        ))
        return try DataPackageCodec.fileWrapper(for: .init(files: files, preferredFilename: "Legacy.periodicdata"))
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController().makeContainer(schema: Schema(versionedSchema: AppSchemaV6.self), inMemory: true)
    }

    private func makeInput(
        id: UUID = UUID(), money: Money = Money(minorUnits: 6_000, currency: .cny),
        sharing: SubscriptionSharingPlan?, billingKind: BillingKind = .recurring
    ) -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: id, name: "Shared", symbolName: "person.2", iconResourceName: nil, iconURLString: nil,
            category: .media, managementState: .active, billingKind: billingKind,
            periodStart: .today, expiry: billingKind == .recurring ? .today : nil,
            cycleMonths: billingKind == .recurring ? 12 : nil, money: money, sharing: sharing,
            note: "", reminderEnabled: billingKind == .recurring, automaticallyRenews: true
        )
    }

    private func organizer() -> SubscriptionSharingPlan {
        .init(role: .organizer, purchaseMoney: price(30_000), members: [
            member(name: "A", money: price(7_000)), member(name: "B", money: price(8_000)),
            member(name: "C", money: price(9_000)),
        ])
    }

    private func participant(amount: Money?) -> SubscriptionSharingPlan {
        .init(role: .participant, purchaseMoney: nil, members: [member(money: amount)])
    }

    private func member(id: UUID = UUID(), name: String = "Other", money: Money? = nil) -> SubscriptionSharingMember {
        .init(id: id, name: name, money: money)
    }

    private func price(_ minorUnits: Int64) -> Money { Money(minorUnits: minorUnits, currency: .cny) }
}
