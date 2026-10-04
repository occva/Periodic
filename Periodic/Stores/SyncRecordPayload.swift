import Foundation

enum SyncRecordPayload {
    static func subscription(
        _ record: SubscriptionRecord,
        sharing: SubscriptionSharingPlan?
    ) throws -> [String: SyncValue] {
        [
            "name": .string(record.name),
            "symbolName": .string(record.symbolName),
            "iconResourceName": value(record.iconResourceName),
            "iconURLString": value(record.iconURLString),
            "categoryRaw": .string(record.categoryRaw),
            "managementStateRaw": .string(record.managementStateRaw),
            "billingKindRaw": .string(record.billingKindRaw),
            "periodStartDay": value(record.periodStartDay),
            "expiryDay": value(record.expiryDay),
            "cycleMonths": value(record.cycleMonths),
            "periodAmountMinor": .integer(record.periodAmountMinor),
            "currencyCode": .string(record.currencyCode),
            "currencyScale": .integer(Int64(record.currencyScale)),
            "note": .string(record.note),
            "reminderEnabled": .bool(record.reminderEnabled),
            "reminderAdvanceDaysRaw": .string(record.reminderAdvanceDaysRaw),
            "reminderMinuteOfDay": .integer(Int64(record.reminderMinuteOfDay)),
            "automaticallyRenews": .bool(record.automaticallyRenews),
            "sharing": try value(sharing),
            "createdAt": .date(record.createdAt),
        ]
    }

    static func period(
        _ record: SubscriptionPeriodRecord,
        sharing: SubscriptionSharingPlan?
    ) throws -> [String: SyncValue] {
        [
            "subscriptionID": .string(record.subscriptionID.uuidString),
            "billingKindRaw": .string(record.billingKindRaw),
            "cycleMonths": value(record.cycleMonths),
            "startDay": .integer(Int64(record.startDay)),
            "endDay": value(record.endDay),
            "amountMinor": .integer(record.amountMinor),
            "currencyCode": .string(record.currencyCode),
            "currencyScale": .integer(Int64(record.currencyScale)),
            "sourceRaw": .string(record.sourceRaw),
            "sharing": try value(sharing),
            "createdAt": .date(record.createdAt),
        ]
    }

    static func payment(
        _ record: SubscriptionPaymentRecord,
        attachmentReferences: [String]
    ) -> [String: SyncValue] {
        [
            "subscriptionID": .string(record.subscriptionID.uuidString),
            "periodRecordID": value(record.periodRecordID),
            "kindRaw": .string(record.kindRaw),
            "paymentDay": .integer(Int64(record.paymentDay)),
            "amountMinor": .integer(record.amountMinor),
            "currencyCode": .string(record.currencyCode),
            "currencyScale": .integer(Int64(record.currencyScale)),
            "periodStartDay": value(record.periodStartDay),
            "periodEndDay": value(record.periodEndDay),
            "note": .string(record.note),
            "attachmentReferences": .array(
                attachmentReferences.map(SyncValue.string)
            ),
            "createdAt": .date(record.createdAt),
        ]
    }

    static func template(
        _ record: ServiceTemplateRecord
    ) throws -> [String: SyncValue] {
        let aliases = try JSONDecoder().decode(
            [String].self,
            from: record.aliasesData
        )
        return [
            "name": .string(record.name),
            "aliases": .array(aliases.map(SyncValue.string)),
            "categoryRaw": .string(record.categoryRaw),
            "customCategoryID": value(record.customCategoryID),
            "symbolName": .string(record.symbolName),
            "iconResourceName": value(record.iconResourceName),
            "iconURLString": value(record.iconURLString),
            "suggestedBillingKindRaw": .string(record.suggestedBillingKindRaw),
            "suggestedCycleMonths": value(record.suggestedCycleMonths),
            "suggestedAmountMinor": value(record.suggestedAmountMinor),
            "currencyCode": .string(record.currencyCode),
            "currencyScale": .integer(Int64(record.currencyScale)),
            "createdAt": .date(record.createdAt),
        ]
    }

    static func category(
        _ record: TemplateCategoryRecord
    ) -> [String: SyncValue] {
        [
            "name": .string(record.name),
            "createdAt": .date(record.createdAt),
        ]
    }

    static func builtinCategoryAssignment(
        _ record: BuiltinTemplateCategoryAssignmentRecord
    ) -> [String: SyncValue] {
        [
            "categoryRaw": .string(record.categoryRaw),
            "customCategoryID": value(record.customCategoryID),
        ]
    }

    static func iconAsset(
        reference: String,
        metadata: CloudAssetMetadata
    ) -> [String: SyncValue] {
        [
            "reference": .string(reference),
            "contentHash": .string(metadata.contentHash),
            "formatRaw": .string(metadata.format.rawValue),
            "byteCount": .integer(Int64(metadata.byteCount)),
        ]
    }

    private static func value(_ value: String?) -> SyncValue {
        value.map(SyncValue.string) ?? .null
    }

    private static func value(_ value: Int?) -> SyncValue {
        value.map { .integer(Int64($0)) } ?? .null
    }

    private static func value(_ value: Int64?) -> SyncValue {
        value.map(SyncValue.integer) ?? .null
    }

    private static func value(_ value: UUID?) -> SyncValue {
        value.map { .string($0.uuidString) } ?? .null
    }

    private static func value(
        _ value: SubscriptionSharingPlan?
    ) throws -> SyncValue {
        guard let value else { return .null }
        return .data(try JSONEncoder().encode(value))
    }
}
