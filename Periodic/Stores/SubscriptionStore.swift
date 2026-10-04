import Foundation
import SwiftData

@ModelActor
actor SubscriptionStore {
    enum StoreError: LocalizedError, Equatable {
        case invalidStoredValue(String)
        case notFound
        case periodNotFound
        case paymentNotFound
        case incompletePeriodDates
        case invalidPaymentDate
        case invalidPaymentAmount
        case invalidPaymentPeriod
        case revisionConflict

        var errorDescription: String? {
            switch self {
            case .invalidStoredValue(let field): "订阅数据的 \(field) 字段无法识别。"
            case .notFound: "这条订阅已不存在。"
            case .periodNotFound: "这条周期记录已不存在。"
            case .paymentNotFound: "这条消费记录已不存在。"
            case .incompletePeriodDates: "开始日期和到期日期必须同时填写，才能添加周期记录。"
            case .invalidPaymentDate: "付款日期不能晚于今天。"
            case .invalidPaymentAmount: "付款金额不能为负数。"
            case .invalidPaymentPeriod: "消费记录关联的周期或覆盖日期无效。"
            case .revisionConflict: "这条订阅已在别处修改，请刷新后重试。"
            }
        }
    }

    private var datasetAccess = DatasetAccessCoordinator()

    init(
        modelContainer: ModelContainer,
        datasetAccess: DatasetAccessCoordinator = DatasetAccessCoordinator()
    ) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.datasetAccess = datasetAccess
    }

    private var sharingPersistence: SubscriptionSharingPersistence {
        SubscriptionSharingPersistence(context: modelContext)
    }

    func fetchAll() throws -> [SubscriptionDTO] {
        let descriptor = FetchDescriptor<SubscriptionRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let records = try modelContext.fetch(descriptor)
        let sharingPlans = try sharingPersistence.plansByOwnerKey(in: .currentSubscriptions)
        var subscriptions: [SubscriptionDTO] = []
        var firstConversionError: (any Error)?
        for record in records {
            do {
                subscriptions.append(try makeDTO(record, sharingPlans: sharingPlans))
            } catch {
                firstConversionError = firstConversionError ?? error
            }
        }
        if subscriptions.isEmpty, !records.isEmpty, let firstConversionError {
            throw firstConversionError
        }
        if firstConversionError != nil {
            AppLog.persistence.warning("Skipped invalid subscription records while loading")
        }
        return subscriptions
    }

    func create(
        _ input: SubscriptionCreateInput,
        historyPolicy: SubscriptionCreationHistoryPolicy = .recordInitialPeriod
    ) async throws -> UUID {
        try await commit {
            try sharingPersistence.set(input.sharing, subscriptionID: input.id, myMoney: input.money)
            let record = SubscriptionRecord(input: input)
            modelContext.insert(record)
            try SyncMutationJournal.recordCreate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscription,
                recordID: record.id.uuidString,
                fieldValues: try SyncRecordPayload.subscription(
                    record,
                    sharing: input.sharing
                )
            )
            if historyPolicy == .recordInitialPeriod,
               let period = initialPeriod(for: input) {
                try insertPeriod(period)
            }
            return input.id
        }
    }

    func create(
        _ inputs: [SubscriptionCreateInput],
        additionalPeriods: [SubscriptionPeriodCreateInput] = []
    ) async throws {
        try await commit {
            for input in inputs {
                try sharingPersistence.set(input.sharing, subscriptionID: input.id, myMoney: input.money)
                let record = SubscriptionRecord(input: input)
                modelContext.insert(record)
                try SyncMutationJournal.recordCreate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscription,
                    recordID: record.id.uuidString,
                    fieldValues: try SyncRecordPayload.subscription(
                        record,
                        sharing: input.sharing
                    )
                )
                if let period = initialPeriod(for: input) {
                    try insertPeriod(period)
                }
            }
            for period in additionalPeriods {
                try insertPeriod(period)
            }
        }
    }

    func fetchPeriods(for subscriptionID: UUID) throws -> [SubscriptionPeriodDTO] {
        let descriptor = FetchDescriptor<SubscriptionPeriodRecord>(
            predicate: #Predicate { $0.subscriptionID == subscriptionID },
            sortBy: [
                SortDescriptor(\.startDay, order: .forward),
                SortDescriptor(\.createdAt, order: .forward),
            ]
        )
        let records = try modelContext.fetch(descriptor)
        let sharingPlans = try sharingPersistence.plansByOwnerKey(in: .subscription(subscriptionID))
        var periods: [SubscriptionPeriodDTO] = []
        var firstConversionError: (any Error)?
        for record in records {
            do {
                periods.append(try makePeriodDTO(record, sharingPlans: sharingPlans))
            } catch {
                firstConversionError = firstConversionError ?? error
            }
        }
        if periods.isEmpty, !records.isEmpty, let firstConversionError {
            throw firstConversionError
        }
        if firstConversionError != nil {
            AppLog.persistence.warning("Skipped invalid subscription period records while loading")
        }
        return periods
    }

    func fetchPayments(for subscriptionID: UUID) throws -> [SubscriptionPaymentDTO] {
        let descriptor = FetchDescriptor<SubscriptionPaymentRecord>(
            predicate: #Predicate { $0.subscriptionID == subscriptionID },
            sortBy: [
                SortDescriptor(\.paymentDay, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
            ]
        )
        let records = try modelContext.fetch(descriptor)
        let attachmentReferences = try paymentAttachmentReferencesByPaymentID(
            paymentIDs: Set(records.map(\.id))
        )
        var payments: [SubscriptionPaymentDTO] = []
        var firstConversionError: (any Error)?
        for record in records {
            do {
                payments.append(try makePaymentDTO(
                    record,
                    attachmentReferences: attachmentReferences[record.id] ?? []
                ))
            } catch {
                firstConversionError = firstConversionError ?? error
            }
        }
        if payments.isEmpty, !records.isEmpty, let firstConversionError {
            throw firstConversionError
        }
        if firstConversionError != nil {
            AppLog.persistence.warning("Skipped invalid subscription payment records while loading")
        }
        return payments
    }

    func fetchDetail(for subscriptionID: UUID) throws -> SubscriptionDetailSnapshot {
        var descriptor = FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.id == subscriptionID }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw StoreError.notFound
        }
        return try SubscriptionDetailSnapshot(
            subscription: makeDTO(record),
            periods: fetchPeriods(for: subscriptionID),
            payments: fetchPayments(for: subscriptionID)
        )
    }

    func referencedPaymentAttachmentReferences() throws -> Set<String> {
        let current = try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>()
        ).map(\.reference)
        let legacy = try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentRecord>()
        ).map(\.reference)
        return Set(current).union(legacy)
    }

    func update(
        _ input: SubscriptionCreateInput,
        expectedRevision: Int64,
        historyPolicy: SubscriptionUpdateHistoryPolicy
    ) async throws {
        try await commit {
            let record = try fetchSubscription(id: input.id, expectedRevision: expectedRevision)
            let previous = try SyncRecordPayload.subscription(
                record,
                sharing: sharingPersistence.plan(subscriptionID: record.id)
            )
            switch historyPolicy {
            case .currentOnly:
                if input.billingKind == .lifetime {
                    try insertLifetimePeriodIfNeeded(
                        for: input,
                        fallbackStart: LocalDate(record.createdAt)
                    )
                }
            case .appendPeriodRecord:
                guard let period = initialPeriod(for: input, source: .manual) else {
                    throw StoreError.incompletePeriodDates
                }
                try insertPeriod(period)
            }
            try sharingPersistence.set(input.sharing, subscriptionID: input.id, myMoney: input.money)
            record.apply(input)
            try SyncMutationJournal.recordUpdate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscription,
                recordID: record.id.uuidString,
                previous: previous,
                current: try SyncRecordPayload.subscription(
                    record,
                    sharing: input.sharing
                ),
                legacyBaseRevision: expectedRevision
            )
        }
    }

    func addPeriod(_ input: SubscriptionPeriodAddInput) async throws {
        try await commit {
            let subscription = try fetchSubscription(
                id: input.period.subscriptionID,
                expectedRevision: input.expectedSubscriptionRevision
            )
            try insertPeriod(input.period)
            subscription.markHistoryChanged()
        }
    }

    func updatePeriod(_ input: SubscriptionPeriodUpdateInput) async throws {
        try await commit {
            let subscription = try fetchSubscription(
                id: input.original.subscriptionID,
                expectedRevision: input.expectedSubscriptionRevision
            )
            let period = try period(matching: input.original)
            let sharing: SubscriptionSharingPlan?
            switch input.sharingUpdate {
            case .preserve:
                sharing = input.original.sharing
            case .replace(let plan):
                sharing = plan
            }
            let previous = try SyncRecordPayload.period(
                period,
                sharing: input.original.sharing
            )
            try sharing?.validate(myMoney: input.money)
            try sharingPersistence.set(
                sharing,
                subscriptionID: period.subscriptionID,
                periodID: period.id,
                myMoney: input.money
            )
            period.apply(input)
            try SyncMutationJournal.recordUpdate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscriptionPeriod,
                recordID: period.id.uuidString,
                previous: previous,
                current: try SyncRecordPayload.period(
                    period,
                    sharing: sharing
                )
            )
            subscription.markHistoryChanged()
        }
    }

    func deletePeriod(_ input: SubscriptionPeriodDeleteInput) async throws {
        try await commit {
            let subscription = try fetchSubscription(
                id: input.original.subscriptionID,
                expectedRevision: input.expectedSubscriptionRevision
            )
            let period = try period(matching: input.original)
            let periodID = period.id
            let linkedPayments = try modelContext.fetch(
                FetchDescriptor<SubscriptionPaymentRecord>(
                    predicate: #Predicate { $0.periodRecordID == periodID }
                )
            )
            for payment in linkedPayments {
                let attachmentReferences = try paymentAttachmentReferencesByPaymentID(
                    paymentIDs: [payment.id]
                )[payment.id] ?? []
                let previous = SyncRecordPayload.payment(
                    payment,
                    attachmentReferences: attachmentReferences
                )
                let baseRevision = payment.revision
                payment.periodRecordID = nil
                payment.revision += 1
                payment.updatedAt = .now
                try SyncMutationJournal.recordUpdate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscriptionPayment,
                    recordID: payment.id.uuidString,
                    previous: previous,
                    current: SyncRecordPayload.payment(
                        payment,
                        attachmentReferences: attachmentReferences
                    ),
                    legacyBaseRevision: baseRevision
                )
            }
            try SyncMutationJournal.recordDelete(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscriptionPeriod,
                recordID: period.id.uuidString
            )
            try sharingPersistence.set(nil, subscriptionID: period.subscriptionID, periodID: period.id, myMoney: input.original.money)
            modelContext.delete(period)
            subscription.markHistoryChanged()
        }
    }

    func addPayment(_ input: SubscriptionPaymentAddInput) async throws {
        try await commit {
            let subscription = try fetchSubscription(
                id: input.payment.subscriptionID,
                expectedRevision: input.expectedSubscriptionRevision
            )
            try validate(input.payment)
            try validatePeriodLink(
                input.payment.periodRecordID,
                subscriptionID: input.payment.subscriptionID
            )
            let payment = SubscriptionPaymentRecord(input: input.payment)
            modelContext.insert(payment)
            try replacePaymentAttachments(
                paymentID: input.payment.id,
                references: input.payment.attachmentReferences
            )
            try SyncMutationJournal.recordCreate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscriptionPayment,
                recordID: payment.id.uuidString,
                fieldValues: SyncRecordPayload.payment(
                    payment,
                    attachmentReferences: input.payment.attachmentReferences
                )
            )
            subscription.markHistoryChanged()
        }
    }

    func updatePayment(_ input: SubscriptionPaymentUpdateInput) async throws {
        try await commit {
            let subscription = try fetchSubscription(
                id: input.original.subscriptionID,
                expectedRevision: input.expectedSubscriptionRevision
            )
            try validate(
                kind: input.original.kind,
                paymentDate: input.paymentDate,
                money: input.money,
                periodStart: input.periodStart,
                periodEnd: input.periodEnd
            )
            try validatePeriodLink(
                input.periodRecordID,
                subscriptionID: input.original.subscriptionID
            )
            let payment = try payment(matching: input.original)
            let previous = SyncRecordPayload.payment(
                payment,
                attachmentReferences: input.original.attachmentReferences
            )
            let baseRevision = payment.revision
            payment.apply(input)
            try replacePaymentAttachments(
                paymentID: payment.id,
                references: input.attachmentReferences
            )
            try SyncMutationJournal.recordUpdate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscriptionPayment,
                recordID: payment.id.uuidString,
                previous: previous,
                current: SyncRecordPayload.payment(
                    payment,
                    attachmentReferences: input.attachmentReferences
                ),
                legacyBaseRevision: baseRevision
            )
            subscription.markHistoryChanged()
        }
    }

    func deletePayment(_ input: SubscriptionPaymentDeleteInput) async throws {
        try await commit {
            let subscription = try fetchSubscription(
                id: input.original.subscriptionID,
                expectedRevision: input.expectedSubscriptionRevision
            )
            let payment = try payment(matching: input.original)
            try SyncMutationJournal.recordDelete(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscriptionPayment,
                recordID: payment.id.uuidString,
                legacyBaseRevision: payment.revision
            )
            try paymentAttachments(paymentID: payment.id).forEach(modelContext.delete)
            try legacyPaymentAttachments(paymentID: payment.id).forEach(modelContext.delete)
            modelContext.delete(payment)
            subscription.markHistoryChanged()
        }
    }

    func previewDeletion(_ targets: [SubscriptionMutationTarget]) throws -> SubscriptionDeletionPreview {
        let uniqueTargets = Dictionary(targets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard !uniqueTargets.isEmpty else {
            return SubscriptionDeletionPreview(
                targets: [],
                subscriptionCount: 0,
                periodCount: 0,
                paymentCount: 0
            )
        }
        let records = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for target in uniqueTargets {
            guard let record = recordsByID[target.id] else { throw StoreError.notFound }
            guard record.revision == target.expectedRevision else {
                throw StoreError.revisionConflict
            }
        }
        let targetIDs = Set(uniqueTargets.map(\.id))
        let periodCount = try modelContext.fetch(FetchDescriptor<SubscriptionPeriodRecord>())
            .count { targetIDs.contains($0.subscriptionID) }
        let paymentCount = try modelContext.fetch(FetchDescriptor<SubscriptionPaymentRecord>())
            .count { targetIDs.contains($0.subscriptionID) }
        return SubscriptionDeletionPreview(
            targets: uniqueTargets,
            subscriptionCount: uniqueTargets.count,
            periodCount: periodCount,
            paymentCount: paymentCount
        )
    }

    func delete(
        _ preview: SubscriptionDeletionPreview
    ) async throws -> SubscriptionDeletionResult {
        try await commit {
            let records = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
            let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            let targetIDs = Set(preview.targets.map(\.id))
            var targets: [SubscriptionRecord] = []
            for target in preview.targets {
                guard let record = recordsByID[target.id] else { throw StoreError.notFound }
                guard record.revision == target.expectedRevision else {
                    throw StoreError.revisionConflict
                }
                targets.append(record)
            }
            let periods = try modelContext.fetch(FetchDescriptor<SubscriptionPeriodRecord>())
                .filter { targetIDs.contains($0.subscriptionID) }
            let payments = try modelContext.fetch(FetchDescriptor<SubscriptionPaymentRecord>())
                .filter { targetIDs.contains($0.subscriptionID) }
            let paymentIDs = Set(payments.map(\.id))
            let paymentAttachments = try modelContext.fetch(
                FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>()
            ).filter { paymentIDs.contains($0.paymentID) }
            let legacyPaymentAttachments = try modelContext.fetch(
                FetchDescriptor<SubscriptionPaymentAttachmentRecord>()
            ).filter { paymentIDs.contains($0.paymentID) }
            guard targets.count == preview.subscriptionCount,
                  periods.count == preview.periodCount,
                  payments.count == preview.paymentCount else {
                throw StoreError.revisionConflict
            }

            let candidateIconReferences = Set(targets.compactMap(\.iconURLString))
            let candidateAttachmentReferences = Set(
                paymentAttachments.map(\.reference)
            ).union(legacyPaymentAttachments.map(\.reference))
            for payment in payments {
                try SyncMutationJournal.recordDelete(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscriptionPayment,
                    recordID: payment.id.uuidString,
                    legacyBaseRevision: payment.revision
                )
            }
            for period in periods {
                try SyncMutationJournal.recordDelete(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscriptionPeriod,
                    recordID: period.id.uuidString
                )
            }
            for target in targets {
                try SyncMutationJournal.recordDelete(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscription,
                    recordID: target.id.uuidString,
                    legacyBaseRevision: target.revision
                )
            }
            for attachment in paymentAttachments { modelContext.delete(attachment) }
            for attachment in legacyPaymentAttachments { modelContext.delete(attachment) }
            for payment in payments { modelContext.delete(payment) }
            try sharingPersistence.delete(subscriptionIDs: targetIDs)
            for period in periods { modelContext.delete(period) }
            for target in targets { modelContext.delete(target) }

            let remainingSubscriptionReferences = Set(
                records
                    .filter { !targetIDs.contains($0.id) }
                    .compactMap(\.iconURLString)
            )
            let templateReferences = Set(
                try modelContext.fetch(FetchDescriptor<ServiceTemplateRecord>())
                    .compactMap(\.iconURLString)
            )
            let remainingAttachmentReferences = Set(
                try modelContext.fetch(
                    FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>()
                )
                    .filter { !paymentIDs.contains($0.paymentID) }
                    .map(\.reference)
            ).union(
                try modelContext.fetch(
                    FetchDescriptor<SubscriptionPaymentAttachmentRecord>()
                )
                    .filter { !paymentIDs.contains($0.paymentID) }
                    .map(\.reference)
            )
            return SubscriptionDeletionResult(
                deletedSubscriptionCount: targets.count,
                deletedPeriodCount: periods.count,
                deletedPaymentCount: payments.count,
                unreferencedIconReferences: candidateIconReferences
                    .subtracting(remainingSubscriptionReferences)
                    .subtracting(templateReferences),
                unreferencedPaymentAttachmentReferences: candidateAttachmentReferences
                    .subtracting(remainingAttachmentReferences)
            )
        }
    }

    func setManagementState(
        _ state: ManagementState,
        for targets: [SubscriptionMutationTarget]
    ) async throws {
        try await commit {
            let uniqueTargets = Dictionary(
                targets.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values
            let records = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
            let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            for target in uniqueTargets {
                guard let record = recordsByID[target.id] else { throw StoreError.notFound }
                guard record.revision == target.expectedRevision else {
                    throw StoreError.revisionConflict
                }
                let previous = try SyncRecordPayload.subscription(
                    record,
                    sharing: sharingPersistence.plan(subscriptionID: record.id)
                )
                record.setManagementState(state)
                try SyncMutationJournal.recordUpdate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscription,
                    recordID: record.id.uuidString,
                    previous: previous,
                    current: try SyncRecordPayload.subscription(
                        record,
                        sharing: sharingPersistence.plan(subscriptionID: record.id)
                    ),
                    legacyBaseRevision: target.expectedRevision
                )
            }
        }
    }

    func confirmAutomaticRenewal(
        _ request: SubscriptionRenewalRequest,
        referenceDate: LocalDate = .today
    ) async throws -> SubscriptionRenewalPreview {
        try await commit {
            let record = try fetchSubscription(
                id: request.subscriptionID,
                expectedRevision: request.expectedRevision
            )
            guard record.expiryDay == request.expectedExpiry.dayNumber else {
                throw StoreError.revisionConflict
            }
            let previous = try SyncRecordPayload.subscription(
                record,
                sharing: sharingPersistence.plan(subscriptionID: record.id)
            )

            let preview = try SubscriptionRenewalRule.preview(
                subscription: makeDTO(record),
                referenceDate: referenceDate,
                cycleMonths: request.cycleMonths,
                money: request.quotedMoney
            )
            guard request.quotedMoney.minorUnits >= 0 else {
                throw StoreError.invalidPaymentAmount
            }
            let periodID = UUID()
            try insertPeriod(
                SubscriptionPeriodCreateInput(
                    id: periodID,
                    subscriptionID: record.id,
                    billingKind: .recurring,
                    cycleMonths: preview.cycleMonths,
                    start: preview.nextStart,
                    end: preview.nextExpiry,
                    money: preview.money,
                    sharing: preview.sharing,
                    source: .renewal
                )
            )
            let payment = SubscriptionPaymentCreateInput(
                id: UUID(),
                subscriptionID: record.id,
                periodRecordID: periodID,
                kind: .renewal,
                paymentDate: request.paymentDate,
                money: request.paymentMoney,
                periodStart: preview.nextStart,
                periodEnd: preview.nextExpiry,
                note: request.paymentNote,
                attachmentReferences: []
            )
            try validate(payment)
            let paymentRecord = SubscriptionPaymentRecord(input: payment)
            modelContext.insert(paymentRecord)
            try SyncMutationJournal.recordCreate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscriptionPayment,
                recordID: paymentRecord.id.uuidString,
                fieldValues: SyncRecordPayload.payment(
                    paymentRecord,
                    attachmentReferences: []
                )
            )
            record.applyRenewal(
                start: preview.nextStart,
                expiry: preview.nextExpiry
            )
            try SyncMutationJournal.recordUpdate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscription,
                recordID: record.id.uuidString,
                previous: previous,
                current: try SyncRecordPayload.subscription(
                    record,
                    sharing: sharingPersistence.plan(subscriptionID: record.id)
                ),
                legacyBaseRevision: request.expectedRevision
            )
            return preview
        }
    }

    func markAutomaticRenewalNotRenewed(
        _ request: SubscriptionNonRenewalRequest,
        referenceDate: LocalDate = .today
    ) async throws {
        try await commit {
            let record = try fetchSubscription(
                id: request.subscriptionID,
                expectedRevision: request.expectedRevision
            )
            guard record.expiryDay == request.expectedExpiry.dayNumber else {
                throw StoreError.revisionConflict
            }
            let subscription = try makeDTO(record)
            _ = try SubscriptionRenewalRule.preview(
                subscription: subscription,
                referenceDate: referenceDate
            )

            let previous = try SyncRecordPayload.subscription(
                record,
                sharing: subscription.sharing
            )
            record.applyNonRenewal()
            try SyncMutationJournal.recordUpdate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .subscription,
                recordID: record.id.uuidString,
                previous: previous,
                current: try SyncRecordPayload.subscription(
                    record,
                    sharing: subscription.sharing
                ),
                legacyBaseRevision: request.expectedRevision
            )
        }
    }

    /// Completes the lifetime-history invariant for data created before the
    /// app began materializing a bounded lifetime period automatically.
    func backfillLifetimePeriods() async throws -> Int {
        let lease = try await datasetAccess.acquireWrite()
        do {
            let subscriptions = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
            let periods = try modelContext.fetch(FetchDescriptor<SubscriptionPeriodRecord>())
            let lifetimePeriods = periods.filter {
                $0.billingKindRaw == BillingKind.lifetime.rawValue
            }
            var subscriptionIDsWithLifetimePeriod = Set(lifetimePeriods.map(\.subscriptionID))
            var changedCount = 0

            for period in lifetimePeriods where period.endDay == nil {
                let sharing = try sharingPersistence.plan(
                    subscriptionID: period.subscriptionID,
                    periodID: period.id
                )
                let previous = try SyncRecordPayload.period(
                    period,
                    sharing: sharing
                )
                period.endDay = LocalDate.defaultLifetimeHistoryEnd.dayNumber
                try SyncMutationJournal.recordUpdate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .subscriptionPeriod,
                    recordID: period.id.uuidString,
                    previous: previous,
                    current: try SyncRecordPayload.period(
                        period,
                        sharing: sharing
                    )
                )
                changedCount += 1
            }

            for subscription in subscriptions where
                subscription.billingKindRaw == BillingKind.lifetime.rawValue
                    && !subscriptionIDsWithLifetimePeriod.contains(subscription.id) {
                guard let currency = CurrencyCode(rawValue: subscription.currencyCode),
                      currency.scale == subscription.currencyScale else {
                    AppLog.persistence.warning(
                        "Skipped lifetime history backfill for a subscription with invalid currency metadata"
                    )
                    continue
                }
                let period = SubscriptionPeriodCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    billingKind: .lifetime,
                    cycleMonths: nil,
                    start: subscription.periodStartDay.map(LocalDate.init(dayNumber:))
                        ?? LocalDate(subscription.createdAt),
                    end: .defaultLifetimeHistoryEnd,
                    money: Money(
                        minorUnits: subscription.periodAmountMinor,
                        currency: currency
                    ),
                    source: .initial
                )
                try insertPeriod(period)
                subscriptionIDsWithLifetimePeriod.insert(subscription.id)
                changedCount += 1
            }

            if changedCount > 0 {
                try DatasetMetadata.advanceRevision(
                    in: modelContext,
                    descriptor: datasetAccess.descriptor
                )
                try modelContext.save()
            }
            await datasetAccess.releaseWrite(lease)
            return changedCount
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    private func commit<Value>(
        _ changes: () throws -> Value
    ) async throws -> Value {
        let lease = try await datasetAccess.acquireWrite()
        do {
            let value = try changes()
            try DatasetMetadata.advanceRevision(
                in: modelContext,
                descriptor: datasetAccess.descriptor
            )
            try modelContext.save()
            await datasetAccess.releaseWrite(lease)
            return value
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    private func fetchSubscription(
        id: UUID,
        expectedRevision: Int64
    ) throws -> SubscriptionRecord {
        let subscriptionID = id
        var descriptor = FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.id == subscriptionID }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw StoreError.notFound
        }
        guard record.revision == expectedRevision else {
            throw StoreError.revisionConflict
        }
        return record
    }

    private func period(
        matching original: SubscriptionPeriodDTO
    ) throws -> SubscriptionPeriodRecord {
        let periodID = original.id
        let subscriptionID = original.subscriptionID
        var descriptor = FetchDescriptor<SubscriptionPeriodRecord>(
            predicate: #Predicate {
                $0.id == periodID && $0.subscriptionID == subscriptionID
            }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw StoreError.periodNotFound
        }
        guard try makePeriodDTO(record) == original else {
            throw StoreError.revisionConflict
        }
        return record
    }

    private func payment(
        matching original: SubscriptionPaymentDTO
    ) throws -> SubscriptionPaymentRecord {
        let paymentID = original.id
        let subscriptionID = original.subscriptionID
        var descriptor = FetchDescriptor<SubscriptionPaymentRecord>(
            predicate: #Predicate {
                $0.id == paymentID && $0.subscriptionID == subscriptionID
            }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw StoreError.paymentNotFound
        }
        let attachmentReferences = try paymentAttachmentReferencesByPaymentID(
            paymentIDs: [record.id]
        )[record.id] ?? []
        guard try makePaymentDTO(
            record,
            attachmentReferences: attachmentReferences
        ) == original else {
            throw StoreError.revisionConflict
        }
        return record
    }

    private func validatePeriodLink(
        _ periodRecordID: UUID?,
        subscriptionID: UUID
    ) throws {
        guard let periodRecordID else { return }
        var descriptor = FetchDescriptor<SubscriptionPeriodRecord>(
            predicate: #Predicate {
                $0.id == periodRecordID && $0.subscriptionID == subscriptionID
            }
        )
        descriptor.fetchLimit = 1
        guard try modelContext.fetch(descriptor).first != nil else {
            throw StoreError.invalidPaymentPeriod
        }
    }

    private func validate(_ input: SubscriptionPaymentCreateInput) throws {
        try validate(
            kind: input.kind,
            paymentDate: input.paymentDate,
            money: input.money,
            periodStart: input.periodStart,
            periodEnd: input.periodEnd
        )
    }

    private func validate(
        kind: SubscriptionPaymentKind,
        paymentDate: LocalDate,
        money: Money,
        periodStart: LocalDate?,
        periodEnd: LocalDate?
    ) throws {
        guard paymentDate <= .today else { throw StoreError.invalidPaymentDate }
        guard money.minorUnits >= 0 else { throw StoreError.invalidPaymentAmount }
        guard (periodStart == nil) == (periodEnd == nil) else {
            throw StoreError.invalidPaymentPeriod
        }
        if kind == .renewal, periodStart == nil {
            throw StoreError.invalidPaymentPeriod
        }
        if let periodStart, let periodEnd, periodStart > periodEnd {
            throw StoreError.invalidPaymentPeriod
        }
    }

    private func makeDTO(
        _ record: SubscriptionRecord,
        sharingPlans: [String: SubscriptionSharingPlan]? = nil
    ) throws -> SubscriptionDTO {
        let sharing: SubscriptionSharingPlan?
        if let sharingPlans {
            sharing = sharingPlans[SubscriptionSharingRecord.key(subscriptionID: record.id)]
        } else {
            sharing = try sharingPersistence.plan(subscriptionID: record.id)
        }

        guard let category = ServiceCategory(rawValue: record.categoryRaw) else {
            throw StoreError.invalidStoredValue("categoryRaw")
        }
        guard let managementState = ManagementState(rawValue: record.managementStateRaw) else {
            throw StoreError.invalidStoredValue("managementStateRaw")
        }
        guard let billingKind = BillingKind(rawValue: record.billingKindRaw) else {
            throw StoreError.invalidStoredValue("billingKindRaw")
        }
        guard let currency = CurrencyCode(rawValue: record.currencyCode),
              currency.scale == record.currencyScale else {
            throw StoreError.invalidStoredValue("currencyCode")
        }

        try sharing?.validate(myMoney: Money(minorUnits: record.periodAmountMinor, currency: currency))
        return SubscriptionDTO(
            id: record.id,
            name: record.name,
            symbolName: record.symbolName,
            iconResourceName: record.iconResourceName,
            iconURLString: record.iconURLString,
            category: category,
            managementState: managementState,
            billingKind: billingKind,
            periodStart: record.periodStartDay.map(LocalDate.init(dayNumber:)),
            expiry: record.expiryDay.map(LocalDate.init(dayNumber:)),
            cycleMonths: record.cycleMonths,
            money: Money(minorUnits: record.periodAmountMinor, currency: currency),
            sharing: sharing,
            note: record.note,
            reminderEnabled: record.reminderEnabled,
            reminderAdvanceDays: SubscriptionNotificationSchedule.advanceDays(
                from: record.reminderAdvanceDaysRaw
            ),
            reminderMinuteOfDay: record.reminderMinuteOfDay,
            automaticallyRenews: record.automaticallyRenews,
            revision: record.revision,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private func makePeriodDTO(
        _ record: SubscriptionPeriodRecord,
        sharingPlans: [String: SubscriptionSharingPlan]? = nil
    ) throws -> SubscriptionPeriodDTO {
        let sharing: SubscriptionSharingPlan?
        if let sharingPlans {
            let key = SubscriptionSharingRecord.key(subscriptionID: record.subscriptionID, periodID: record.id)
            sharing = sharingPlans[key]
        } else {
            sharing = try sharingPersistence.plan(subscriptionID: record.subscriptionID, periodID: record.id)
        }

        guard let billingKind = BillingKind(rawValue: record.billingKindRaw) else {
            throw StoreError.invalidStoredValue("period.billingKindRaw")
        }
        guard let currency = CurrencyCode(rawValue: record.currencyCode),
              currency.scale == record.currencyScale else {
            throw StoreError.invalidStoredValue("period.currencyCode")
        }
        guard let source = SubscriptionPeriodSource(rawValue: record.sourceRaw) else {
            throw StoreError.invalidStoredValue("period.sourceRaw")
        }
        try sharing?.validate(myMoney: Money(minorUnits: record.amountMinor, currency: currency))
        return SubscriptionPeriodDTO(
            id: record.id,
            subscriptionID: record.subscriptionID,
            billingKind: billingKind,
            cycleMonths: record.cycleMonths,
            start: LocalDate(dayNumber: record.startDay),
            end: record.endDay.map(LocalDate.init(dayNumber:)),
            money: Money(minorUnits: record.amountMinor, currency: currency),
            sharing: sharing,
            source: source,
            createdAt: record.createdAt
        )
    }

    private func makePaymentDTO(
        _ record: SubscriptionPaymentRecord,
        attachmentReferences: [String]
    ) throws -> SubscriptionPaymentDTO {
        guard let kind = SubscriptionPaymentKind(rawValue: record.kindRaw) else {
            throw StoreError.invalidStoredValue("payment.kindRaw")
        }
        guard let currency = CurrencyCode(rawValue: record.currencyCode),
              currency.scale == record.currencyScale else {
            throw StoreError.invalidStoredValue("payment.currencyCode")
        }
        guard attachmentReferences.allSatisfy(PaymentAttachmentReference.isValid),
              PaymentAttachmentReference.removingDuplicates(attachmentReferences)
                == attachmentReferences else {
            throw StoreError.invalidStoredValue("payment.attachmentReferences")
        }
        return SubscriptionPaymentDTO(
            id: record.id,
            subscriptionID: record.subscriptionID,
            periodRecordID: record.periodRecordID,
            kind: kind,
            paymentDate: LocalDate(dayNumber: record.paymentDay),
            money: Money(minorUnits: record.amountMinor, currency: currency),
            periodStart: record.periodStartDay.map(LocalDate.init(dayNumber:)),
            periodEnd: record.periodEndDay.map(LocalDate.init(dayNumber:)),
            note: record.note,
            attachmentReferences: attachmentReferences,
            revision: record.revision,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private func paymentAttachmentReferencesByPaymentID(
        paymentIDs: Set<UUID>
    ) throws -> [UUID: [String]] {
        guard !paymentIDs.isEmpty else { return [:] }
        let paymentIDs = Array(paymentIDs)
        let current = Dictionary(
            grouping: try modelContext.fetch(
                FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>(
                    predicate: #Predicate { paymentIDs.contains($0.paymentID) }
                )
            ),
            by: \.paymentID
        ).mapValues { records in
            records.sorted {
                ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString)
            }.map(\.reference)
        }
        let legacy = try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentRecord>(
                predicate: #Predicate { paymentIDs.contains($0.paymentID) }
            )
        )
        return legacy.reduce(into: current) { result, record in
            if result[record.paymentID] == nil {
                result[record.paymentID] = [record.reference]
            }
        }
    }

    private func paymentAttachments(
        paymentID: UUID
    ) throws -> [SubscriptionPaymentAttachmentItemRecord] {
        let descriptor = FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>(
            predicate: #Predicate { $0.paymentID == paymentID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func legacyPaymentAttachments(
        paymentID: UUID
    ) throws -> [SubscriptionPaymentAttachmentRecord] {
        let descriptor = FetchDescriptor<SubscriptionPaymentAttachmentRecord>(
            predicate: #Predicate { $0.paymentID == paymentID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func replacePaymentAttachments(
        paymentID: UUID,
        references: [String]
    ) throws {
        let references = PaymentAttachmentReference.removingDuplicates(references)
        guard references.allSatisfy(PaymentAttachmentReference.isValid) else {
            throw StoreError.invalidStoredValue("payment.attachmentReferences")
        }
        try paymentAttachments(paymentID: paymentID).forEach(modelContext.delete)
        try legacyPaymentAttachments(paymentID: paymentID).forEach(modelContext.delete)
        for (sortOrder, reference) in references.enumerated() {
            modelContext.insert(
                SubscriptionPaymentAttachmentItemRecord(
                    paymentID: paymentID,
                    reference: reference,
                    sortOrder: sortOrder
                )
            )
        }
    }

    private func insertPeriod(_ input: SubscriptionPeriodCreateInput) throws {
        try sharingPersistence.set(
            input.sharing,
            subscriptionID: input.subscriptionID,
            periodID: input.id,
            myMoney: input.money
        )
        let record = SubscriptionPeriodRecord(input: input)
        modelContext.insert(record)
        try SyncMutationJournal.recordCreate(
            in: modelContext,
            deviceID: datasetAccess.deviceID,
            recordType: .subscriptionPeriod,
            recordID: record.id.uuidString,
            fieldValues: try SyncRecordPayload.period(
                record,
                sharing: input.sharing
            )
        )
    }

    private func initialPeriod(
        for input: SubscriptionCreateInput,
        fallbackStart: LocalDate = .today,
        source: SubscriptionPeriodSource = .initial
    ) -> SubscriptionPeriodCreateInput? {
        switch input.billingKind {
        case .recurring:
            guard let start = input.periodStart, let expiry = input.expiry else { return nil }
            return SubscriptionPeriodCreateInput(
                id: UUID(),
                subscriptionID: input.id,
                billingKind: .recurring,
                cycleMonths: input.cycleMonths,
                start: start,
                end: expiry,
                money: input.money,
                sharing: input.sharing,
                source: source
            )
        case .lifetime:
            return SubscriptionPeriodCreateInput(
                id: UUID(),
                subscriptionID: input.id,
                billingKind: .lifetime,
                cycleMonths: nil,
                start: input.periodStart ?? fallbackStart,
                end: .defaultLifetimeHistoryEnd,
                money: input.money,
                sharing: input.sharing,
                source: source
            )
        }
    }

    private func insertLifetimePeriodIfNeeded(
        for input: SubscriptionCreateInput,
        fallbackStart: LocalDate
    ) throws {
        let subscriptionID = input.id
        let lifetimeRawValue = BillingKind.lifetime.rawValue
        var descriptor = FetchDescriptor<SubscriptionPeriodRecord>(
            predicate: #Predicate {
                $0.subscriptionID == subscriptionID
                    && $0.billingKindRaw == lifetimeRawValue
            }
        )
        descriptor.fetchLimit = 1
        guard try modelContext.fetch(descriptor).isEmpty else {
            return
        }
        guard let period = initialPeriod(
            for: input,
            fallbackStart: fallbackStart,
            source: .manual
        ) else { return }
        try insertPeriod(period)
    }
}
