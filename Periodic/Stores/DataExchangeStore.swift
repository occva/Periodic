import CryptoKit
import Foundation
import SwiftData

@ModelActor
actor DataExchangeStore {
    func snapshot() throws -> DataPackageSnapshot {
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
                    automaticallyRenews: record.automaticallyRenews,
                    revision: record.revision,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
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
                    createdAt: record.createdAt
                )
            }
            .sorted {
                ($0.subscriptionID.uuidString, $0.start.dayNumber, $0.id.uuidString)
                    < ($1.subscriptionID.uuidString, $1.start.dayNumber, $1.id.uuidString)
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

    func referencedIconReferences() throws -> Set<String> {
        let subscriptionReferences = try modelContext
            .fetch(FetchDescriptor<SubscriptionRecord>())
            .compactMap(\.iconURLString)
        let templateReferences = try modelContext
            .fetch(FetchDescriptor<ServiceTemplateRecord>())
            .compactMap(\.iconURLString)
        return Set(subscriptionReferences).union(templateReferences)
    }

    func preview(imported: DataPackageSnapshot) throws -> DataImportPreview {
        let local = try snapshot()
        return DataImportPreview(
            subscriptions: changes(local.subscriptions, imported.subscriptions),
            periods: changes(local.periods, imported.periods),
            templates: changes(local.templates, imported.templates),
            categories: changes(local.categories, imported.categories),
            assignments: changes(local.builtinCategoryAssignments, imported.builtinCategoryAssignments),
            assetCount: 0
        )
    }

    func execute(
        imported: DataPackageSnapshot,
        expectedDigest: String,
        conflictResolution: DataImportConflictResolution
    ) throws -> DataImportReceipt {
        guard try digest() == expectedDigest else { throw DataExchangeError.stalePlan }
        do {
            let local = try snapshot()
            let localCategoriesByID = Dictionary(uniqueKeysWithValues: local.categories.map { ($0.id, $0) })
            let localSubscriptionsByID = Dictionary(uniqueKeysWithValues: local.subscriptions.map { ($0.id, $0) })
            let localPeriodsByID = Dictionary(uniqueKeysWithValues: local.periods.map { ($0.id, $0) })
            let localTemplatesByID = Dictionary(uniqueKeysWithValues: local.templates.map { ($0.id, $0) })
            let localAssignmentsByKey = Dictionary(
                uniqueKeysWithValues: local.builtinCategoryAssignments.map { ($0.templateKey, $0) }
            )
            var added = 0
            var updated = 0
            var skipped = 0

            let categories = try modelContext.fetch(FetchDescriptor<TemplateCategoryRecord>())
            let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            for incoming in imported.categories {
                if let record = categoriesByID[incoming.id] {
                    if localCategoriesByID[incoming.id] == incoming {
                        skipped += 1
                    } else if conflictResolution == .useImported {
                        apply(incoming, to: record)
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    modelContext.insert(makeCategory(incoming))
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
                        apply(incoming, to: record)
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    modelContext.insert(makeSubscription(incoming))
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
                        apply(incoming, to: record)
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    modelContext.insert(makePeriod(incoming))
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
                        try apply(incoming, to: record)
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    modelContext.insert(try makeTemplate(incoming))
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
                        apply(incoming, to: record)
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    modelContext.insert(makeAssignment(incoming))
                    added += 1
                }
            }

            try modelContext.save()
            return DataImportReceipt(added: added, updated: updated, skipped: skipped)
        } catch {
            modelContext.rollback()
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

    private func makeSubscription(_ value: DataPackageSubscription) -> SubscriptionRecord {
        let record = SubscriptionRecord(input: subscriptionInput(value), now: value.createdAt)
        apply(value, to: record)
        record.revision = 1
        record.createdAt = value.createdAt
        record.updatedAt = value.updatedAt
        return record
    }

    private func apply(_ value: DataPackageSubscription, to record: SubscriptionRecord) {
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
            note: value.note,
            reminderEnabled: value.reminderEnabled,
            automaticallyRenews: value.automaticallyRenews
        )
    }

    private func makePeriod(_ value: DataPackagePeriod) -> SubscriptionPeriodRecord {
        SubscriptionPeriodRecord(
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

    private func apply(_ value: DataPackagePeriod, to record: SubscriptionPeriodRecord) {
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
