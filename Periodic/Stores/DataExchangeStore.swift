import CryptoKit
import Foundation
import SwiftData

@ModelActor
actor DataExchangeStore {
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

    func snapshot() throws -> DataPackageSnapshot {
        let sharingPlans = try sharingPersistence.plansByOwnerKey()
        let paymentAttachmentReferences = try paymentAttachmentReferencesByPaymentID()
        let subscriptions = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
            .map { record in
                DataPackageSubscription(
                    recordVersion: 1,
                    id: record.id,
                    name: record.name,
                    symbolName: record.symbolName,
                    iconResourceName: record.iconResourceName,
                    iconAssetID: record.iconURLString,
                    category: try value(ServiceCategory.self, raw: record.categoryRaw, field: "subscription.category"),
                    managementState: try value(ManagementState.self, raw: record.managementStateRaw, field: "subscription.managementState"),
                    billingKind: try value(BillingKind.self, raw: record.billingKindRaw, field: "subscription.billingKind"),
                    periodStart: record.periodStartDay.map(LocalDate.init(dayNumber:)),
                    expiry: record.expiryDay.map(LocalDate.init(dayNumber:)),
                    cycleMonths: record.cycleMonths,
                    amountMinor: record.periodAmountMinor,
                    currency: try currency(record.currencyCode, scale: record.currencyScale),
                    currencyScale: record.currencyScale,
                    note: record.note,
                    reminderEnabled: record.reminderEnabled,
                    reminderAdvanceDays: SubscriptionNotificationSchedule.advanceDays(
                        from: record.reminderAdvanceDaysRaw
                    ),
                    reminderMinuteOfDay: record.reminderMinuteOfDay,
                    automaticallyRenews: record.automaticallyRenews,
                    revision: record.revision,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    sharing: sharingPlans[SubscriptionSharingRecord.key(subscriptionID: record.id)]
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let periods = try modelContext.fetch(FetchDescriptor<SubscriptionPeriodRecord>())
            .map { record in
                DataPackagePeriod(
                    recordVersion: 1,
                    id: record.id,
                    subscriptionID: record.subscriptionID,
                    billingKind: try value(BillingKind.self, raw: record.billingKindRaw, field: "period.billingKind"),
                    cycleMonths: record.cycleMonths,
                    start: LocalDate(dayNumber: record.startDay),
                    end: record.endDay.map(LocalDate.init(dayNumber:)),
                    amountMinor: record.amountMinor,
                    currency: try currency(record.currencyCode, scale: record.currencyScale),
                    currencyScale: record.currencyScale,
                    source: try value(SubscriptionPeriodSource.self, raw: record.sourceRaw, field: "period.source"),
                    createdAt: record.createdAt,
                    sharing: sharingPlans[SubscriptionSharingRecord.key(subscriptionID: record.subscriptionID, periodID: record.id)]
                )
            }
            .sorted {
                ($0.subscriptionID.uuidString, $0.start.dayNumber, $0.id.uuidString)
                    < ($1.subscriptionID.uuidString, $1.start.dayNumber, $1.id.uuidString)
            }

        let payments = try modelContext.fetch(FetchDescriptor<SubscriptionPaymentRecord>())
            .map { record in
                DataPackagePayment(
                    recordVersion: 1,
                    id: record.id,
                    subscriptionID: record.subscriptionID,
                    periodRecordID: record.periodRecordID,
                    kind: try value(
                        SubscriptionPaymentKind.self,
                        raw: record.kindRaw,
                        field: "payment.kind"
                    ),
                    paymentDate: LocalDate(dayNumber: record.paymentDay),
                    amountMinor: record.amountMinor,
                    currency: try currency(record.currencyCode, scale: record.currencyScale),
                    currencyScale: record.currencyScale,
                    periodStart: record.periodStartDay.map(LocalDate.init(dayNumber:)),
                    periodEnd: record.periodEndDay.map(LocalDate.init(dayNumber:)),
                    note: record.note,
                    attachmentAssetIDs: paymentAttachmentReferences[record.id] ?? [],
                    revision: record.revision,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
            }
            .sorted {
                ($0.subscriptionID.uuidString, $0.paymentDate.dayNumber, $0.id.uuidString)
                    < ($1.subscriptionID.uuidString, $1.paymentDate.dayNumber, $1.id.uuidString)
            }

        let templates = try modelContext.fetch(FetchDescriptor<ServiceTemplateRecord>())
            .map { record in
                DataPackageTemplate(
                    recordVersion: 1,
                    id: record.id,
                    name: record.name,
                    aliases: try JSONDecoder().decode([String].self, from: record.aliasesData),
                    category: try value(ServiceCategory.self, raw: record.categoryRaw, field: "template.category"),
                    customCategoryID: record.customCategoryID,
                    symbolName: record.symbolName,
                    iconResourceName: record.iconResourceName,
                    iconAssetID: record.iconURLString,
                    suggestedBillingKind: try value(BillingKind.self, raw: record.suggestedBillingKindRaw, field: "template.billingKind"),
                    suggestedCycleMonths: record.suggestedCycleMonths,
                    suggestedAmountMinor: record.suggestedAmountMinor,
                    currency: try currency(record.currencyCode, scale: record.currencyScale),
                    currencyScale: record.currencyScale,
                    revision: record.revision,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let categories = try modelContext.fetch(FetchDescriptor<TemplateCategoryRecord>())
            .map {
                DataPackageCategory(
                    recordVersion: 1,
                    id: $0.id,
                    name: $0.name,
                    revision: $0.revision,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let assignments = try modelContext.fetch(
            FetchDescriptor<BuiltinTemplateCategoryAssignmentRecord>()
        )
            .map {
                DataPackageBuiltinCategoryAssignment(
                    recordVersion: 1,
                    templateKey: $0.templateKey,
                    category: try value(ServiceCategory.self, raw: $0.categoryRaw, field: "assignment.category"),
                    customCategoryID: $0.customCategoryID,
                    updatedAt: $0.updatedAt
                )
            }
            .sorted { $0.templateKey < $1.templateKey }

        return DataPackageSnapshot(
            subscriptions: subscriptions,
            periods: periods,
            payments: payments,
            templates: templates,
            categories: categories,
            builtinCategoryAssignments: assignments,
            settings: nil
        )
    }

    func digest() throws -> String {
        let data = try DataPackageCodec.canonicalSnapshotData(snapshot())
        return DataPackageCodec.sha256(data)
    }

    func version() async throws -> DatasetVersion {
        let lease = try await datasetAccess.acquireWrite()
        do {
            let version = try DatasetMetadata.currentVersion(
                in: modelContext,
                descriptor: datasetAccess.descriptor
            )
            if modelContext.hasChanges {
                try modelContext.save()
            }
            await datasetAccess.releaseWrite(lease)
            return version
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    func referencedIconReferences() throws -> Set<String> {
        let subscriptionReferences = try modelContext
            .fetch(FetchDescriptor<SubscriptionRecord>())
            .compactMap(\.iconURLString)
        let templateReferences = try modelContext
            .fetch(FetchDescriptor<ServiceTemplateRecord>())
            .compactMap(\.iconURLString)
        return Set(subscriptionReferences).union(templateReferences)
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

    func preview(imported: DataPackageSnapshot) throws -> DataImportPreview {
        let local = try snapshot()
        return DataImportPreview(
            subscriptions: changes(local.subscriptions, imported.subscriptions),
            periods: changes(local.periods, imported.periods),
            payments: changes(local.payments, imported.payments),
            templates: changes(local.templates, imported.templates),
            categories: changes(local.categories, imported.categories),
            assignments: changes(local.builtinCategoryAssignments, imported.builtinCategoryAssignments),
            assetCount: 0
        )
    }

    func execute(
        imported: DataPackageSnapshot,
        expectedDigest: String,
        expectedVersion: DatasetVersion? = nil,
        conflictResolution: DataImportConflictResolution
    ) async throws -> DataImportReceipt {
        for value in imported.subscriptions {
            try value.sharing?.validate(myMoney: Money(minorUnits: value.amountMinor, currency: value.currency))
        }
        for value in imported.periods {
            try value.sharing?.validate(myMoney: Money(minorUnits: value.amountMinor, currency: value.currency))
        }
        let lease = try await datasetAccess.acquireWrite()
        do {
            guard try digest() == expectedDigest else {
                throw DataExchangeError.stalePlan
            }
            if let expectedVersion {
                let currentVersion = try DatasetMetadata.currentVersion(
                    in: modelContext,
                    descriptor: datasetAccess.descriptor
                )
                guard currentVersion == expectedVersion else {
                    throw DataExchangeError.stalePlan
                }
            }
            let local = try snapshot()
            let localCategoriesByID = Dictionary(uniqueKeysWithValues: local.categories.map { ($0.id, $0) })
            let localSubscriptionsByID = Dictionary(uniqueKeysWithValues: local.subscriptions.map { ($0.id, $0) })
            let localPeriodsByID = Dictionary(uniqueKeysWithValues: local.periods.map { ($0.id, $0) })
            let localPaymentsByID = Dictionary(uniqueKeysWithValues: local.payments.map { ($0.id, $0) })
            let localTemplatesByID = Dictionary(uniqueKeysWithValues: local.templates.map { ($0.id, $0) })
            let localAssignmentsByKey = Dictionary(
                uniqueKeysWithValues: local.builtinCategoryAssignments.map { ($0.templateKey, $0) }
            )
            var added = 0
            var updated = 0
            var skipped = 0
            var updatedSubscriptionIDs = Set<UUID>()
            var changedHistorySubscriptionIDs = Set<UUID>()

            let categories = try modelContext.fetch(FetchDescriptor<TemplateCategoryRecord>())
            let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            for incoming in imported.categories {
                if let record = categoriesByID[incoming.id] {
                    if localCategoriesByID[incoming.id] == incoming {
                        skipped += 1
                    } else if conflictResolution == .useImported {
                        let previous = SyncRecordPayload.category(record)
                        let baseRevision = record.revision
                        apply(incoming, to: record)
                        try SyncMutationJournal.recordUpdate(
                            in: modelContext,
                            deviceID: datasetAccess.deviceID,
                            recordType: .templateCategory,
                            recordID: record.id.uuidString,
                            previous: previous,
                            current: SyncRecordPayload.category(record),
                            legacyBaseRevision: baseRevision
                        )
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    let record = makeCategory(incoming)
                    modelContext.insert(record)
                    try SyncMutationJournal.recordCreate(
                        in: modelContext,
                        deviceID: datasetAccess.deviceID,
                        recordType: .templateCategory,
                        recordID: record.id.uuidString,
                        fieldValues: SyncRecordPayload.category(record)
                    )
                    added += 1
                }
            }

            let subscriptions = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
            let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
            for incoming in imported.subscriptions {
                if let record = subscriptionsByID[incoming.id] {
                    if localSubscriptionsByID[incoming.id] == incoming {
                        skipped += 1
                    } else if conflictResolution == .useImported {
                        let previous = try SyncRecordPayload.subscription(
                            record,
                            sharing: localSubscriptionsByID[incoming.id]?.sharing
                        )
                        let baseRevision = record.revision
                        try apply(incoming, to: record)
                        try SyncMutationJournal.recordUpdate(
                            in: modelContext,
                            deviceID: datasetAccess.deviceID,
                            recordType: .subscription,
                            recordID: record.id.uuidString,
                            previous: previous,
                            current: try SyncRecordPayload.subscription(
                                record,
                                sharing: incoming.sharing
                            ),
                            legacyBaseRevision: baseRevision
                        )
                        updatedSubscriptionIDs.insert(record.id)
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    let record = try makeSubscription(incoming)
                    modelContext.insert(record)
                    try SyncMutationJournal.recordCreate(
                        in: modelContext,
                        deviceID: datasetAccess.deviceID,
                        recordType: .subscription,
                        recordID: record.id.uuidString,
                        fieldValues: try SyncRecordPayload.subscription(
                            record,
                            sharing: incoming.sharing
                        )
                    )
                    added += 1
                }
            }

            let validSubscriptionIDs = Set(local.subscriptions.map(\.id))
                .union(imported.subscriptions.map(\.id))
            let periods = try modelContext.fetch(FetchDescriptor<SubscriptionPeriodRecord>())
            let periodsByID = Dictionary(uniqueKeysWithValues: periods.map { ($0.id, $0) })
            for incoming in imported.periods {
                guard validSubscriptionIDs.contains(incoming.subscriptionID) else {
                    throw DataExchangeError.invalidRecord("周期缺少对应订阅")
                }
                if let record = periodsByID[incoming.id] {
                    if localPeriodsByID[incoming.id] == incoming {
                        skipped += 1
                    } else if conflictResolution == .useImported {
                        changedHistorySubscriptionIDs.insert(record.subscriptionID)
                        let previous = try SyncRecordPayload.period(
                            record,
                            sharing: localPeriodsByID[incoming.id]?.sharing
                        )
                        try apply(incoming, to: record)
                        try SyncMutationJournal.recordUpdate(
                            in: modelContext,
                            deviceID: datasetAccess.deviceID,
                            recordType: .subscriptionPeriod,
                            recordID: record.id.uuidString,
                            previous: previous,
                            current: try SyncRecordPayload.period(
                                record,
                                sharing: incoming.sharing
                            )
                        )
                        changedHistorySubscriptionIDs.insert(incoming.subscriptionID)
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    let record = try makePeriod(incoming)
                    modelContext.insert(record)
                    try SyncMutationJournal.recordCreate(
                        in: modelContext,
                        deviceID: datasetAccess.deviceID,
                        recordType: .subscriptionPeriod,
                        recordID: record.id.uuidString,
                        fieldValues: try SyncRecordPayload.period(
                            record,
                            sharing: incoming.sharing
                        )
                    )
                    changedHistorySubscriptionIDs.insert(incoming.subscriptionID)
                    added += 1
                }
            }

            let payments = try modelContext.fetch(FetchDescriptor<SubscriptionPaymentRecord>())
            let paymentsByID = Dictionary(uniqueKeysWithValues: payments.map { ($0.id, $0) })
            let paymentAttachments = try modelContext.fetch(
                FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>()
            )
            let paymentAttachmentsByPaymentID = Dictionary(
                grouping: paymentAttachments,
                by: \.paymentID
            )
            let importedPeriodsByID = Dictionary(
                uniqueKeysWithValues: imported.periods.map { ($0.id, $0) }
            )
            for incoming in imported.payments {
                guard validSubscriptionIDs.contains(incoming.subscriptionID) else {
                    throw DataExchangeError.invalidRecord("消费记录缺少对应订阅")
                }
                if let periodID = incoming.periodRecordID {
                    let linkedSubscriptionID = periodsByID[periodID]?.subscriptionID
                        ?? importedPeriodsByID[periodID]?.subscriptionID
                    guard linkedSubscriptionID == incoming.subscriptionID else {
                        throw DataExchangeError.invalidRecord("消费记录缺少对应周期")
                    }
                }
                if let record = paymentsByID[incoming.id] {
                    if localPaymentsByID[incoming.id] == incoming {
                        skipped += 1
                    } else if conflictResolution == .useImported {
                        changedHistorySubscriptionIDs.insert(record.subscriptionID)
                        let previous = SyncRecordPayload.payment(
                            record,
                            attachmentReferences: localPaymentsByID[incoming.id]?
                                .attachmentAssetIDs ?? []
                        )
                        let baseRevision = record.revision
                        apply(incoming, to: record)
                        try replacePaymentAttachments(
                            incoming.attachmentAssetIDs,
                            paymentID: incoming.id,
                            existing: paymentAttachmentsByPaymentID[incoming.id] ?? []
                        )
                        try SyncMutationJournal.recordUpdate(
                            in: modelContext,
                            deviceID: datasetAccess.deviceID,
                            recordType: .subscriptionPayment,
                            recordID: record.id.uuidString,
                            previous: previous,
                            current: SyncRecordPayload.payment(
                                record,
                                attachmentReferences: incoming.attachmentAssetIDs
                            ),
                            legacyBaseRevision: baseRevision
                        )
                        changedHistorySubscriptionIDs.insert(incoming.subscriptionID)
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    let record = makePayment(incoming)
                    modelContext.insert(record)
                    try replacePaymentAttachments(
                        incoming.attachmentAssetIDs,
                        paymentID: incoming.id,
                        existing: []
                    )
                    try SyncMutationJournal.recordCreate(
                        in: modelContext,
                        deviceID: datasetAccess.deviceID,
                        recordType: .subscriptionPayment,
                        recordID: record.id.uuidString,
                        fieldValues: SyncRecordPayload.payment(
                            record,
                            attachmentReferences: incoming.attachmentAssetIDs
                        )
                    )
                    changedHistorySubscriptionIDs.insert(incoming.subscriptionID)
                    added += 1
                }
            }

            let validCategoryIDs = Set(local.categories.map(\.id)).union(imported.categories.map(\.id))
            let templates = try modelContext.fetch(FetchDescriptor<ServiceTemplateRecord>())
            let templatesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
            for incoming in imported.templates {
                if let categoryID = incoming.customCategoryID,
                   !validCategoryIDs.contains(categoryID) {
                    throw DataExchangeError.invalidRecord("模板缺少对应自定义分类")
                }
                if let record = templatesByID[incoming.id] {
                    if localTemplatesByID[incoming.id] == incoming {
                        skipped += 1
                    } else if conflictResolution == .useImported {
                        let previous = try SyncRecordPayload.template(record)
                        let baseRevision = record.revision
                        try apply(incoming, to: record)
                        try SyncMutationJournal.recordUpdate(
                            in: modelContext,
                            deviceID: datasetAccess.deviceID,
                            recordType: .serviceTemplate,
                            recordID: record.id.uuidString,
                            previous: previous,
                            current: try SyncRecordPayload.template(record),
                            legacyBaseRevision: baseRevision
                        )
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    let record = try makeTemplate(incoming)
                    modelContext.insert(record)
                    try SyncMutationJournal.recordCreate(
                        in: modelContext,
                        deviceID: datasetAccess.deviceID,
                        recordType: .serviceTemplate,
                        recordID: record.id.uuidString,
                        fieldValues: try SyncRecordPayload.template(record)
                    )
                    added += 1
                }
            }

            let assignments = try modelContext.fetch(
                FetchDescriptor<BuiltinTemplateCategoryAssignmentRecord>()
            )
            let assignmentsByKey = Dictionary(uniqueKeysWithValues: assignments.map { ($0.templateKey, $0) })
            for incoming in imported.builtinCategoryAssignments {
                if let categoryID = incoming.customCategoryID,
                   !validCategoryIDs.contains(categoryID) {
                    throw DataExchangeError.invalidRecord("内置模板覆盖缺少对应自定义分类")
                }
                if let record = assignmentsByKey[incoming.templateKey] {
                    if localAssignmentsByKey[incoming.templateKey] == incoming {
                        skipped += 1
                    } else if conflictResolution == .useImported {
                        let previous = SyncRecordPayload
                            .builtinCategoryAssignment(record)
                        apply(incoming, to: record)
                        try SyncMutationJournal.recordUpdate(
                            in: modelContext,
                            deviceID: datasetAccess.deviceID,
                            recordType: .builtinTemplateCategoryAssignment,
                            recordID: record.templateKey,
                            previous: previous,
                            current: SyncRecordPayload
                                .builtinCategoryAssignment(record)
                        )
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    let record = makeAssignment(incoming)
                    modelContext.insert(record)
                    try SyncMutationJournal.recordCreate(
                        in: modelContext,
                        deviceID: datasetAccess.deviceID,
                        recordType: .builtinTemplateCategoryAssignment,
                        recordID: record.templateKey,
                        fieldValues: SyncRecordPayload
                            .builtinCategoryAssignment(record)
                    )
                    added += 1
                }
            }

            for subscription in subscriptions where
                changedHistorySubscriptionIDs.contains(subscription.id)
                    && !updatedSubscriptionIDs.contains(subscription.id) {
                subscription.markHistoryChanged()
            }
            if added > 0 || updated > 0 {
                try DatasetMetadata.advanceRevision(
                    in: modelContext,
                    descriptor: datasetAccess.descriptor
                )
                try modelContext.save()
            }
            let receipt = DataImportReceipt(added: added, updated: updated, skipped: skipped)
            await datasetAccess.releaseWrite(lease)
            return receipt
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    private func changes<T: Identifiable & Equatable>(
        _ local: [T],
        _ imported: [T]
    ) -> DataImportPreview.EntityChanges where T.ID: Hashable {
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var additions = 0
        var conflicts = 0
        var unchanged = 0
        for record in imported {
            guard let existing = localByID[record.id] else {
                additions += 1
                continue
            }
            if existing == record { unchanged += 1 } else { conflicts += 1 }
        }
        return .init(additions: additions, conflicts: conflicts, unchanged: unchanged)
    }

    private func makeSubscription(_ value: DataPackageSubscription) throws -> SubscriptionRecord {
        let record = SubscriptionRecord(input: subscriptionInput(value), now: value.createdAt)
        try apply(value, to: record)
        record.revision = 1
        record.createdAt = value.createdAt
        record.updatedAt = value.updatedAt
        return record
    }

    private func apply(_ value: DataPackageSubscription, to record: SubscriptionRecord) throws {
        try sharingPersistence.set(
            value.sharing,
            subscriptionID: value.id,
            myMoney: Money(minorUnits: value.amountMinor, currency: value.currency)
        )
        record.name = value.name
        record.symbolName = value.symbolName
        record.iconResourceName = value.iconResourceName
        record.iconURLString = value.iconAssetID
        record.categoryRaw = value.category.rawValue
        record.managementStateRaw = value.managementState.rawValue
        record.billingKindRaw = value.billingKind.rawValue
        record.periodStartDay = value.periodStart?.dayNumber
        record.expiryDay = value.expiry?.dayNumber
        record.cycleMonths = value.cycleMonths
        record.periodAmountMinor = value.amountMinor
        record.currencyCode = value.currency.rawValue
        record.currencyScale = value.currencyScale
        record.note = value.note
        record.reminderEnabled = value.reminderEnabled
        record.reminderAdvanceDaysRaw = SubscriptionNotificationSchedule.storedAdvanceDays(
            value.reminderAdvanceDays
                ?? SubscriptionNotificationSchedule.defaultAdvanceDays
        )
        record.reminderMinuteOfDay = SubscriptionNotificationSchedule.normalizedMinuteOfDay(
            value.reminderMinuteOfDay
                ?? SubscriptionNotificationSchedule.defaultMinuteOfDay
        )
        record.automaticallyRenews = value.automaticallyRenews
        record.revision = max(record.revision + 1, 1)
        record.updatedAt = .now
    }

    private func subscriptionInput(_ value: DataPackageSubscription) -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: value.id,
            name: value.name,
            symbolName: value.symbolName,
            iconResourceName: value.iconResourceName,
            iconURLString: value.iconAssetID,
            category: value.category,
            managementState: value.managementState,
            billingKind: value.billingKind,
            periodStart: value.periodStart,
            expiry: value.expiry,
            cycleMonths: value.cycleMonths,
            money: Money(minorUnits: value.amountMinor, currency: value.currency),
            sharing: value.sharing,
            note: value.note,
            reminderEnabled: value.reminderEnabled,
            reminderAdvanceDays: value.reminderAdvanceDays
                ?? SubscriptionNotificationSchedule.defaultAdvanceDays,
            reminderMinuteOfDay: value.reminderMinuteOfDay
                ?? SubscriptionNotificationSchedule.defaultMinuteOfDay,
            automaticallyRenews: value.automaticallyRenews
        )
    }

    private func makePeriod(_ value: DataPackagePeriod) throws -> SubscriptionPeriodRecord {
        try sharingPersistence.set(
            value.sharing, subscriptionID: value.subscriptionID, periodID: value.id,
            myMoney: Money(minorUnits: value.amountMinor, currency: value.currency)
        )
        return SubscriptionPeriodRecord(
            input: SubscriptionPeriodCreateInput(
                id: value.id,
                subscriptionID: value.subscriptionID,
                billingKind: value.billingKind,
                cycleMonths: value.cycleMonths,
                start: value.start,
                end: value.end,
                money: Money(minorUnits: value.amountMinor, currency: value.currency),
                source: value.source
            ),
            now: value.createdAt
        )
    }

    private func apply(_ value: DataPackagePeriod, to record: SubscriptionPeriodRecord) throws {
        try sharingPersistence.set(
            value.sharing, subscriptionID: value.subscriptionID, periodID: value.id,
            myMoney: Money(minorUnits: value.amountMinor, currency: value.currency)
        )
        record.subscriptionID = value.subscriptionID
        record.billingKindRaw = value.billingKind.rawValue
        record.cycleMonths = value.cycleMonths
        record.startDay = value.start.dayNumber
        record.endDay = value.end?.dayNumber
        record.amountMinor = value.amountMinor
        record.currencyCode = value.currency.rawValue
        record.currencyScale = value.currencyScale
        record.sourceRaw = value.source.rawValue
        record.createdAt = value.createdAt
    }

    private func makePayment(_ value: DataPackagePayment) -> SubscriptionPaymentRecord {
        let record = SubscriptionPaymentRecord(
            input: SubscriptionPaymentCreateInput(
                id: value.id,
                subscriptionID: value.subscriptionID,
                periodRecordID: value.periodRecordID,
                kind: value.kind,
                paymentDate: value.paymentDate,
                money: Money(minorUnits: value.amountMinor, currency: value.currency),
                periodStart: value.periodStart,
                periodEnd: value.periodEnd,
                note: value.note,
                attachmentReferences: []
            ),
            now: value.createdAt
        )
        apply(value, to: record)
        record.revision = max(value.revision, 1)
        record.createdAt = value.createdAt
        record.updatedAt = value.updatedAt
        return record
    }

    private func apply(_ value: DataPackagePayment, to record: SubscriptionPaymentRecord) {
        record.subscriptionID = value.subscriptionID
        record.periodRecordID = value.periodRecordID
        record.kindRaw = value.kind.rawValue
        record.paymentDay = value.paymentDate.dayNumber
        record.amountMinor = value.amountMinor
        record.currencyCode = value.currency.rawValue
        record.currencyScale = value.currencyScale
        record.periodStartDay = value.periodStart?.dayNumber
        record.periodEndDay = value.periodEnd?.dayNumber
        record.note = value.note
        record.revision = max(record.revision + 1, 1)
        record.updatedAt = .now
    }

    private func replacePaymentAttachments(
        _ references: [String],
        paymentID: UUID,
        existing: [SubscriptionPaymentAttachmentItemRecord]
    ) throws {
        let references = PaymentAttachmentReference.removingDuplicates(references)
        guard references.allSatisfy(PaymentAttachmentReference.isValid) else {
            throw DataExchangeError.invalidRecord("消费截图引用无效")
        }
        existing.forEach(modelContext.delete)
        let targetPaymentID = paymentID
        let legacyDescriptor = FetchDescriptor<SubscriptionPaymentAttachmentRecord>(
            predicate: #Predicate { $0.paymentID == targetPaymentID }
        )
        try modelContext.fetch(legacyDescriptor).forEach(modelContext.delete)
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

    private func paymentAttachmentReferencesByPaymentID() throws -> [UUID: [String]] {
        let current = Dictionary(
            grouping: try modelContext.fetch(
                FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>()
            ),
            by: \.paymentID
        ).mapValues { records in
            records.sorted {
                ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString)
            }.map(\.reference)
        }
        let legacy = try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentRecord>()
        )
        return legacy.reduce(into: current) { result, record in
            if result[record.paymentID] == nil {
                result[record.paymentID] = [record.reference]
            }
        }
    }

    private func makeTemplate(_ value: DataPackageTemplate) throws -> ServiceTemplateRecord {
        let record = ServiceTemplateRecord(
            input: templateInput(value),
            aliasesData: try JSONEncoder().encode(value.aliases),
            now: value.createdAt
        )
        try apply(value, to: record)
        record.revision = 1
        record.createdAt = value.createdAt
        record.updatedAt = value.updatedAt
        return record
    }

    private func apply(_ value: DataPackageTemplate, to record: ServiceTemplateRecord) throws {
        record.name = value.name
        record.aliasesData = try JSONEncoder().encode(value.aliases)
        record.categoryRaw = value.category.rawValue
        record.customCategoryID = value.customCategoryID
        record.symbolName = value.symbolName
        record.iconResourceName = value.iconResourceName
        record.iconURLString = value.iconAssetID
        record.suggestedBillingKindRaw = value.suggestedBillingKind.rawValue
        record.suggestedCycleMonths = value.suggestedCycleMonths
        record.suggestedAmountMinor = value.suggestedAmountMinor
        record.currencyCode = value.currency.rawValue
        record.currencyScale = value.currencyScale
        record.revision = max(record.revision + 1, 1)
        record.updatedAt = .now
    }

    private func templateInput(_ value: DataPackageTemplate) -> ServiceTemplateInput {
        ServiceTemplateInput(
            id: value.id,
            expectedRevision: nil,
            name: value.name,
            aliases: value.aliases,
            category: value.category,
            customCategoryID: value.customCategoryID,
            symbolName: value.symbolName,
            iconResourceName: value.iconResourceName,
            iconURLString: value.iconAssetID,
            suggestedBillingKind: value.suggestedBillingKind,
            suggestedCycleMonths: value.suggestedCycleMonths,
            suggestedMoney: value.suggestedAmountMinor.map {
                Money(minorUnits: $0, currency: value.currency)
            },
            currency: value.currency
        )
    }

    private func makeCategory(_ value: DataPackageCategory) -> TemplateCategoryRecord {
        let record = TemplateCategoryRecord(
            input: TemplateCategoryInput(id: value.id, expectedRevision: nil, name: value.name),
            now: value.createdAt
        )
        apply(value, to: record)
        record.revision = 1
        record.createdAt = value.createdAt
        record.updatedAt = value.updatedAt
        return record
    }

    private func apply(_ value: DataPackageCategory, to record: TemplateCategoryRecord) {
        record.name = value.name
        record.revision = max(record.revision + 1, 1)
        record.updatedAt = .now
    }

    private func makeAssignment(
        _ value: DataPackageBuiltinCategoryAssignment
    ) -> BuiltinTemplateCategoryAssignmentRecord {
        let record = BuiltinTemplateCategoryAssignmentRecord(
            templateKey: value.templateKey,
            assignment: assignment(value),
            now: value.updatedAt
        )
        apply(value, to: record)
        return record
    }

    private func apply(
        _ value: DataPackageBuiltinCategoryAssignment,
        to record: BuiltinTemplateCategoryAssignmentRecord
    ) {
        record.categoryRaw = value.category.rawValue
        record.customCategoryID = value.customCategoryID
        record.updatedAt = .now
    }

    private func assignment(
        _ value: DataPackageBuiltinCategoryAssignment
    ) -> TemplateCategoryAssignment {
        value.customCategoryID.map(TemplateCategoryAssignment.custom)
            ?? .builtin(value.category)
    }

    private func currency(_ raw: String, scale: Int) throws -> CurrencyCode {
        guard let value = CurrencyCode(rawValue: raw), value.scale == scale else {
            throw DataExchangeError.invalidRecord("货币元数据不一致")
        }
        return value
    }

    private func value<T: RawRepresentable>(
        _ type: T.Type,
        raw: String,
        field: String
    ) throws -> T where T.RawValue == String {
        guard let value = T(rawValue: raw) else {
            throw DataExchangeError.invalidRecord(String(
                format: AppLocalization.string("%@ 无法识别"),
                field
            ))
        }
        return value
    }
}
