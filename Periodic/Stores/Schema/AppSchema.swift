import Foundation
import SwiftData

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            SubscriptionRecord.self,
            SubscriptionPeriodRecord.self,
            ServiceTemplateRecord.self,
            TemplateCategoryRecord.self,
            BuiltinTemplateCategoryAssignmentRecord.self,
        ]
    }

    @Model
    final class SubscriptionRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var symbolName: String
        var iconResourceName: String?
        var iconURLString: String?
        var categoryRaw: String
        var managementStateRaw: String
        var billingKindRaw: String
        var periodStartDay: Int?
        var expiryDay: Int?
        var cycleMonths: Int?
        var periodAmountMinor: Int64
        var currencyCode: String
        var currencyScale: Int
        var note: String
        var reminderEnabled: Bool
        var automaticallyRenews: Bool = false
        var revision: Int64
        var createdAt: Date
        var updatedAt: Date

        init(input: SubscriptionCreateInput, now: Date = Date()) {
            id = input.id
            name = input.name
            symbolName = input.symbolName
            iconResourceName = input.iconResourceName
            iconURLString = input.iconURLString
            categoryRaw = input.category.rawValue
            managementStateRaw = input.managementState.rawValue
            billingKindRaw = input.billingKind.rawValue
            periodStartDay = input.periodStart?.dayNumber
            expiryDay = input.expiry?.dayNumber
            cycleMonths = input.cycleMonths
            periodAmountMinor = input.money.minorUnits
            currencyCode = input.money.currency.rawValue
            currencyScale = input.money.currency.scale
            note = input.note
            reminderEnabled = input.reminderEnabled
            automaticallyRenews = input.automaticallyRenews
            revision = 1
            createdAt = now
            updatedAt = now
        }
    }

    @Model
    final class SubscriptionPeriodRecord {
        @Attribute(.unique) var id: UUID
        var subscriptionID: UUID
        var billingKindRaw: String
        var cycleMonths: Int?
        var startDay: Int
        var endDay: Int?
        var amountMinor: Int64
        var currencyCode: String
        var currencyScale: Int
        // SwiftData applies this default to rows created before source tracking existed.
        // Their exact origin cannot be reconstructed without risking false history.
        var sourceRaw: String = SubscriptionPeriodSource.legacy.rawValue
        var createdAt: Date

        init(input: SubscriptionPeriodCreateInput, now: Date = Date()) {
            id = input.id
            subscriptionID = input.subscriptionID
            billingKindRaw = input.billingKind.rawValue
            cycleMonths = input.cycleMonths
            startDay = input.start.dayNumber
            endDay = input.end?.dayNumber
            amountMinor = input.money.minorUnits
            currencyCode = input.money.currency.rawValue
            currencyScale = input.money.currency.scale
            sourceRaw = input.source.rawValue
            createdAt = now
        }

        func apply(_ input: SubscriptionPeriodUpdateInput) {
            billingKindRaw = input.billingKind.rawValue
            cycleMonths = input.cycleMonths
            startDay = input.start.dayNumber
            endDay = input.end?.dayNumber
            amountMinor = input.money.minorUnits
            currencyCode = input.money.currency.rawValue
            currencyScale = input.money.currency.scale
        }
    }

    @Model
    final class ServiceTemplateRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var aliasesData: Data
        var categoryRaw: String
        var customCategoryID: UUID?
        var symbolName: String
        var iconResourceName: String?
        var iconURLString: String?
        var suggestedBillingKindRaw: String
        var suggestedCycleMonths: Int?
        var suggestedAmountMinor: Int64?
        var currencyCode: String
        var currencyScale: Int
        var revision: Int64
        var createdAt: Date
        var updatedAt: Date

        init(input: ServiceTemplateInput, aliasesData: Data, now: Date = Date()) {
            id = input.id
            name = input.name
            self.aliasesData = aliasesData
            categoryRaw = input.category.rawValue
            customCategoryID = input.customCategoryID
            symbolName = input.symbolName
            iconResourceName = input.iconResourceName
            iconURLString = input.iconURLString
            suggestedBillingKindRaw = input.suggestedBillingKind.rawValue
            suggestedCycleMonths = input.suggestedCycleMonths
            suggestedAmountMinor = input.suggestedMoney?.minorUnits
            currencyCode = input.currency.rawValue
            currencyScale = input.currency.scale
            revision = 1
            createdAt = now
            updatedAt = now
        }

        func apply(_ input: ServiceTemplateInput, aliasesData: Data, now: Date = Date()) {
            name = input.name
            self.aliasesData = aliasesData
            categoryRaw = input.category.rawValue
            customCategoryID = input.customCategoryID
            symbolName = input.symbolName
            iconResourceName = input.iconResourceName
            iconURLString = input.iconURLString
            suggestedBillingKindRaw = input.suggestedBillingKind.rawValue
            suggestedCycleMonths = input.suggestedCycleMonths
            suggestedAmountMinor = input.suggestedMoney?.minorUnits
            currencyCode = input.currency.rawValue
            currencyScale = input.currency.scale
            revision += 1
            updatedAt = now
        }
    }

    @Model
    final class TemplateCategoryRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var revision: Int64
        var createdAt: Date
        var updatedAt: Date

        init(input: TemplateCategoryInput, now: Date = Date()) {
            id = input.id
            name = input.name
            revision = 1
            createdAt = now
            updatedAt = now
        }

        func apply(_ input: TemplateCategoryInput, now: Date = Date()) {
            name = input.name
            revision += 1
            updatedAt = now
        }
    }

    @Model
    final class BuiltinTemplateCategoryAssignmentRecord {
        @Attribute(.unique) var templateKey: String
        var categoryRaw: String
        var customCategoryID: UUID?
        var updatedAt: Date

        init(
            templateKey: String,
            assignment: TemplateCategoryAssignment,
            now: Date = Date()
        ) {
            self.templateKey = templateKey
            categoryRaw = assignment.category.rawValue
            customCategoryID = assignment.customCategoryID
            updatedAt = now
        }

        func apply(_ assignment: TemplateCategoryAssignment, now: Date = Date()) {
            categoryRaw = assignment.category.rawValue
            customCategoryID = assignment.customCategoryID
            updatedAt = now
        }
    }
}

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            SubscriptionRecord.self,
            SubscriptionPeriodRecord.self,
            ServiceTemplateRecord.self,
            TemplateCategoryRecord.self,
            BuiltinTemplateCategoryAssignmentRecord.self,
        ]
    }
}

enum AppSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            SubscriptionRecord.self,
            SubscriptionPeriodRecord.self,
            SubscriptionPaymentRecord.self,
            ServiceTemplateRecord.self,
            TemplateCategoryRecord.self,
            BuiltinTemplateCategoryAssignmentRecord.self,
        ]
    }
}

enum AppSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            SubscriptionRecord.self,
            SubscriptionPeriodRecord.self,
            SubscriptionPaymentRecord.self,
            SubscriptionPaymentAttachmentRecord.self,
            ServiceTemplateRecord.self,
            TemplateCategoryRecord.self,
            BuiltinTemplateCategoryAssignmentRecord.self,
        ]
    }
}

enum AppSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            SubscriptionRecord.self,
            SubscriptionPeriodRecord.self,
            SubscriptionPaymentRecord.self,
            SubscriptionPaymentAttachmentRecord.self,
            SubscriptionPaymentAttachmentItemRecord.self,
            ServiceTemplateRecord.self,
            TemplateCategoryRecord.self,
            BuiltinTemplateCategoryAssignmentRecord.self,
        ]
    }
}

enum AppSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        AppSchemaV5.models + [SubscriptionSharingRecord.self]
    }
}

enum AppSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        AppSchemaV6.models + [DatasetMetadataRecord.self]
    }
}

enum AppSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        AppSchemaV7.models + [
            SyncMutationRecord.self,
            SyncRecordStateRecord.self,
        ]
    }

    /// Frozen V8 shape. Later versions added CloudKit system fields, so V8 must
    /// retain the exact model checksum already written to existing stores.
    @Model
    final class SyncRecordStateRecord {
        @Attribute(.unique) var recordKey: String
        var recordTypeRaw: String
        var recordID: String
        var revision: Int64
        var modifiedAt: Date
        var modifiedByDeviceID: UUID
        var isDeleted: Bool
        var deletedAt: Date?

        init(
            recordType: SyncRecordType,
            recordID: String,
            revision: Int64,
            modifiedAt: Date,
            modifiedByDeviceID: UUID,
            isDeleted: Bool,
            deletedAt: Date?
        ) {
            recordKey = recordType.rawValue + ":" + recordID
            recordTypeRaw = recordType.rawValue
            self.recordID = recordID
            self.revision = revision
            self.modifiedAt = modifiedAt
            self.modifiedByDeviceID = modifiedByDeviceID
            self.isDeleted = isDeleted
            self.deletedAt = deletedAt
        }
    }
}

enum AppSchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }

    static var models: [any PersistentModel.Type] {
        AppSchemaV7.models + [
            SyncMutationRecord.self,
            SyncRecordStateRecord.self,
            SyncRemoteChangeRecord.self,
            SyncConflictRecord.self,
        ]
    }
}

enum AppSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            AppSchemaV1.self,
            AppSchemaV2.self,
            AppSchemaV3.self,
            AppSchemaV4.self,
            AppSchemaV5.self,
            AppSchemaV6.self,
            AppSchemaV7.self,
            AppSchemaV8.self,
            AppSchemaV9.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self),
            .lightweight(fromVersion: AppSchemaV2.self, toVersion: AppSchemaV3.self),
            .lightweight(fromVersion: AppSchemaV3.self, toVersion: AppSchemaV4.self),
            .custom(
                fromVersion: AppSchemaV4.self,
                toVersion: AppSchemaV5.self,
                willMigrate: nil,
                didMigrate: migratePaymentAttachmentsToOrderedItems
            ),
            .lightweight(fromVersion: AppSchemaV5.self, toVersion: AppSchemaV6.self),
            .lightweight(fromVersion: AppSchemaV6.self, toVersion: AppSchemaV7.self),
            .lightweight(fromVersion: AppSchemaV7.self, toVersion: AppSchemaV8.self),
            .lightweight(fromVersion: AppSchemaV8.self, toVersion: AppSchemaV9.self),
        ]
    }

    private static func migratePaymentAttachmentsToOrderedItems(
        context: ModelContext
    ) throws {
        let legacyAttachments = try context.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentRecord>()
        )
        for attachment in legacyAttachments {
            context.insert(
                SubscriptionPaymentAttachmentItemRecord(
                    paymentID: attachment.paymentID,
                    reference: attachment.reference,
                    sortOrder: 0
                )
            )
            context.delete(attachment)
        }
        try context.save()
    }
}
