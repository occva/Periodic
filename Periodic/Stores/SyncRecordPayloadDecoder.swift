import Foundation

enum SyncRecordPayloadDecoder {
    struct SubscriptionPayload: Sendable {
        let input: SubscriptionCreateInput
        let createdAt: Date
    }

    struct PeriodPayload: Sendable {
        let input: SubscriptionPeriodCreateInput
        let createdAt: Date
    }

    struct PaymentPayload: Sendable {
        let input: SubscriptionPaymentCreateInput
        let createdAt: Date
    }

    struct TemplatePayload: Sendable {
        let input: ServiceTemplateInput
        let aliasesData: Data
        let createdAt: Date
    }

    struct CategoryPayload: Sendable {
        let input: TemplateCategoryInput
        let createdAt: Date
    }

    struct BuiltinCategoryAssignmentPayload: Sendable {
        let templateKey: String
        let assignment: TemplateCategoryAssignment
    }

    struct IconAssetPayload: Sendable {
        let reference: String
        let metadata: CloudAssetMetadata
    }

    enum PayloadError: LocalizedError, Equatable {
        case missingField(String)
        case invalidField(String)
        case invalidDateRange
        case invalidBillingConfiguration
        case invalidMoney

        var errorDescription: String? {
            switch self {
            case .missingField(let field):
                "iCloud 记录缺少 \(field) 字段。"
            case .invalidField(let field):
                "iCloud 记录的 \(field) 字段无效。"
            case .invalidDateRange:
                "iCloud 记录的日期范围无效。"
            case .invalidBillingConfiguration:
                "iCloud 记录的计费类型与周期不一致。"
            case .invalidMoney:
                "iCloud 记录的金额或币种无效。"
            }
        }
    }

    static func subscription(
        recordID: String,
        fieldValues: [String: SyncValue]
    ) throws -> SubscriptionPayload {
        let values = Values(fieldValues)
        let id = try uuid(recordID, field: "recordID")
        let name = try values.string("name")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw PayloadError.invalidField("name")
        }
        let category = try rawValue(
            ServiceCategory.self,
            try values.string("categoryRaw"),
            field: "categoryRaw"
        )
        let managementState = try rawValue(
            ManagementState.self,
            try values.string("managementStateRaw"),
            field: "managementStateRaw"
        )
        let billingKind = try rawValue(
            BillingKind.self,
            try values.string("billingKindRaw"),
            field: "billingKindRaw"
        )
        let periodStart = try values.optionalInt("periodStartDay")
            .map(LocalDate.init(dayNumber:))
        let expiry = try values.optionalInt("expiryDay")
            .map(LocalDate.init(dayNumber:))
        if let periodStart, let expiry, periodStart > expiry {
            throw PayloadError.invalidDateRange
        }
        let cycleMonths = try values.optionalInt("cycleMonths")
        try validateBilling(
            billingKind: billingKind,
            cycleMonths: cycleMonths
        )
        guard billingKind == .recurring || expiry == nil else {
            throw PayloadError.invalidBillingConfiguration
        }
        let money = try money(values)
        let reminderAdvanceDaysRaw = try values.string(
            "reminderAdvanceDaysRaw"
        )
        let reminderAdvanceDays = try reminderDays(
            storedValue: reminderAdvanceDaysRaw
        )
        let reminderMinuteOfDay = try values.int("reminderMinuteOfDay")
        guard (0...(23 * 60 + 59)).contains(reminderMinuteOfDay) else {
            throw PayloadError.invalidField("reminderMinuteOfDay")
        }
        let reminderEnabled = try values.bool("reminderEnabled")
        let automaticallyRenews = try values.bool("automaticallyRenews")
        guard billingKind == .recurring
                || (!reminderEnabled && !automaticallyRenews) else {
            throw PayloadError.invalidBillingConfiguration
        }
        guard managementState == .active || !automaticallyRenews else {
            throw PayloadError.invalidBillingConfiguration
        }
        let sharing = try values.optionalData("sharing").map {
            try JSONDecoder().decode(SubscriptionSharingPlan.self, from: $0)
        }
        try sharing?.validate(myMoney: money)
        let input = SubscriptionCreateInput(
            id: id,
            name: name,
            symbolName: try values.string("symbolName"),
            iconResourceName: try values.optionalString("iconResourceName"),
            iconURLString: try values.optionalString("iconURLString"),
            category: category,
            managementState: managementState,
            billingKind: billingKind,
            periodStart: periodStart,
            expiry: expiry,
            cycleMonths: cycleMonths,
            money: money,
            sharing: sharing,
            note: try values.string("note"),
            reminderEnabled: reminderEnabled,
            reminderAdvanceDays: reminderAdvanceDays,
            reminderMinuteOfDay: reminderMinuteOfDay,
            automaticallyRenews: automaticallyRenews
        )
        guard input.automaticallyRenews == automaticallyRenews else {
            throw PayloadError.invalidBillingConfiguration
        }
        return SubscriptionPayload(
            input: input,
            createdAt: try values.date("createdAt")
        )
    }

    static func period(
        recordID: String,
        fieldValues: [String: SyncValue]
    ) throws -> PeriodPayload {
        let values = Values(fieldValues)
        let billingKind = try rawValue(
            BillingKind.self,
            try values.string("billingKindRaw"),
            field: "billingKindRaw"
        )
        let cycleMonths = try values.optionalInt("cycleMonths")
        let start = LocalDate(dayNumber: try values.int("startDay"))
        let end = try values.optionalInt("endDay")
            .map(LocalDate.init(dayNumber:))
        if let end, start > end {
            throw PayloadError.invalidDateRange
        }
        try validateBilling(
            billingKind: billingKind,
            cycleMonths: cycleMonths
        )
        let money = try money(values)
        let sharing = try values.optionalData("sharing").map {
            try JSONDecoder().decode(SubscriptionSharingPlan.self, from: $0)
        }
        try sharing?.validate(myMoney: money)
        return PeriodPayload(
            input: SubscriptionPeriodCreateInput(
                id: try uuid(recordID, field: "recordID"),
                subscriptionID: try uuid(
                    values.string("subscriptionID"),
                    field: "subscriptionID"
                ),
                billingKind: billingKind,
                cycleMonths: cycleMonths,
                start: start,
                end: end,
                money: money,
                sharing: sharing,
                source: try rawValue(
                    SubscriptionPeriodSource.self,
                    values.string("sourceRaw"),
                    field: "sourceRaw"
                )
            ),
            createdAt: try values.date("createdAt")
        )
    }

    static func payment(
        recordID: String,
        fieldValues: [String: SyncValue]
    ) throws -> PaymentPayload {
        let values = Values(fieldValues)
        let paymentDay = LocalDate(dayNumber: try values.int("paymentDay"))
        guard paymentDay <= .today else {
            throw PayloadError.invalidField("paymentDay")
        }
        let periodStart = try values.optionalInt("periodStartDay")
            .map(LocalDate.init(dayNumber:))
        let periodEnd = try values.optionalInt("periodEndDay")
            .map(LocalDate.init(dayNumber:))
        guard (periodStart == nil) == (periodEnd == nil) else {
            throw PayloadError.invalidDateRange
        }
        if let periodStart, let periodEnd, periodStart > periodEnd {
            throw PayloadError.invalidDateRange
        }
        let kind = try rawValue(
            SubscriptionPaymentKind.self,
            try values.string("kindRaw"),
            field: "kindRaw"
        )
        guard kind != .renewal || periodStart != nil else {
            throw PayloadError.invalidDateRange
        }
        let attachmentReferences = try values.stringArray(
            "attachmentReferences"
        )
        guard attachmentReferences.allSatisfy(
            PaymentAttachmentReference.isValid
        ),
        PaymentAttachmentReference.removingDuplicates(attachmentReferences)
            == attachmentReferences else {
            throw PayloadError.invalidField("attachmentReferences")
        }
        return PaymentPayload(
            input: SubscriptionPaymentCreateInput(
                id: try uuid(recordID, field: "recordID"),
                subscriptionID: try uuid(
                    values.string("subscriptionID"),
                    field: "subscriptionID"
                ),
                periodRecordID: try values.optionalUUID("periodRecordID"),
                kind: kind,
                paymentDate: paymentDay,
                money: try money(values),
                periodStart: periodStart,
                periodEnd: periodEnd,
                note: try values.string("note"),
                attachmentReferences: attachmentReferences
            ),
            createdAt: try values.date("createdAt")
        )
    }

    static func template(
        recordID: String,
        fieldValues: [String: SyncValue]
    ) throws -> TemplatePayload {
        let values = Values(fieldValues)
        let name = try values.string("name")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw PayloadError.invalidField("name")
        }
        let aliases = try values.stringArray("aliases")
        guard normalizedAliases(aliases) == aliases else {
            throw PayloadError.invalidField("aliases")
        }
        let category = try rawValue(
            ServiceCategory.self,
            try values.string("categoryRaw"),
            field: "categoryRaw"
        )
        let customCategoryID = try values.optionalUUID("customCategoryID")
        guard customCategoryID == nil || category == .other else {
            throw PayloadError.invalidField("customCategoryID")
        }
        let billingKind = try rawValue(
            BillingKind.self,
            try values.string("suggestedBillingKindRaw"),
            field: "suggestedBillingKindRaw"
        )
        let cycleMonths = try values.optionalInt("suggestedCycleMonths")
        try validateBilling(
            billingKind: billingKind,
            cycleMonths: cycleMonths
        )
        let currency = try currency(values)
        let suggestedMoney = try values.optionalInteger(
            "suggestedAmountMinor"
        ).map {
            guard $0 >= 0 else {
                throw PayloadError.invalidMoney
            }
            return Money(minorUnits: $0, currency: currency)
        }
        return TemplatePayload(
            input: ServiceTemplateInput(
                id: try uuid(recordID, field: "recordID"),
                expectedRevision: nil,
                name: name,
                aliases: aliases,
                category: category,
                customCategoryID: customCategoryID,
                symbolName: try values.string("symbolName"),
                iconResourceName: try values.optionalString(
                    "iconResourceName"
                ),
                iconURLString: try values.optionalString("iconURLString"),
                suggestedBillingKind: billingKind,
                suggestedCycleMonths: cycleMonths,
                suggestedMoney: suggestedMoney,
                currency: currency
            ),
            aliasesData: try JSONEncoder().encode(aliases),
            createdAt: try values.date("createdAt")
        )
    }

    static func category(
        recordID: String,
        fieldValues: [String: SyncValue]
    ) throws -> CategoryPayload {
        let values = Values(fieldValues)
        let name = try values.string("name")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw PayloadError.invalidField("name")
        }
        return CategoryPayload(
            input: TemplateCategoryInput(
                id: try uuid(recordID, field: "recordID"),
                expectedRevision: nil,
                name: name
            ),
            createdAt: try values.date("createdAt")
        )
    }

    static func builtinCategoryAssignment(
        recordID: String,
        fieldValues: [String: SyncValue]
    ) throws -> BuiltinCategoryAssignmentPayload {
        guard !recordID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PayloadError.invalidField("recordID")
        }
        let values = Values(fieldValues)
        let category = try rawValue(
            ServiceCategory.self,
            try values.string("categoryRaw"),
            field: "categoryRaw"
        )
        let customCategoryID = try values.optionalUUID("customCategoryID")
        let assignment: TemplateCategoryAssignment
        if let customCategoryID {
            guard category == .other else {
                throw PayloadError.invalidField("customCategoryID")
            }
            assignment = .custom(customCategoryID)
        } else {
            assignment = .builtin(category)
        }
        return BuiltinCategoryAssignmentPayload(
            templateKey: recordID,
            assignment: assignment
        )
    }

    static func iconAsset(
        recordID: String,
        fieldValues: [String: SyncValue]
    ) throws -> IconAssetPayload {
        let values = Values(fieldValues)
        let reference = try values.string("reference")
        let contentHash = try values.string("contentHash").lowercased()
        let byteCount = try values.int("byteCount")
        guard reference == recordID,
              CloudAssetRepository.isSupportedReference(reference),
              contentHash.count == 64,
              contentHash.allSatisfy(\.isHexDigit),
              let format = ImageAssetFormat(
                rawValue: try values.string("formatRaw")
              ),
              byteCount > 0,
              byteCount <= ImageAssetValidator.maximumImageSize else {
            throw PayloadError.invalidField("reference")
        }
        if let expectedHash = CloudAssetRepository.contentHash(
            encodedIn: reference
        ), expectedHash != contentHash {
            throw PayloadError.invalidField("contentHash")
        }
        return IconAssetPayload(
            reference: reference,
            metadata: CloudAssetMetadata(
                contentHash: contentHash,
                format: format,
                byteCount: byteCount
            )
        )
    }

    private static func money(_ values: Values) throws -> Money {
        let amount = try values.integer("periodAmountMinor", fallback: "amountMinor")
        guard amount >= 0 else {
            throw PayloadError.invalidMoney
        }
        let currency = try currency(values)
        return Money(minorUnits: amount, currency: currency)
    }

    private static func currency(_ values: Values) throws -> CurrencyCode {
        let scale = try values.int("currencyScale")
        guard let currency = CurrencyCode(
            rawValue: try values.string("currencyCode")
        ),
        currency.scale == scale else {
            throw PayloadError.invalidMoney
        }
        return currency
    }

    private static func validateBilling(
        billingKind: BillingKind,
        cycleMonths: Int?
    ) throws {
        switch billingKind {
        case .recurring:
            guard let cycleMonths, cycleMonths > 0 else {
                throw PayloadError.invalidBillingConfiguration
            }
        case .lifetime:
            guard cycleMonths == nil else {
                throw PayloadError.invalidBillingConfiguration
            }
        }
    }

    private static func reminderDays(storedValue: String) throws -> [Int] {
        let components = storedValue.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        let values = try components.map { component -> Int in
            guard let value = Int(component), value >= 0 else {
                throw PayloadError.invalidField("reminderAdvanceDaysRaw")
            }
            return value
        }
        let normalized = SubscriptionNotificationSchedule
            .normalizedAdvanceDays(values)
        guard !normalized.isEmpty,
              SubscriptionNotificationSchedule.storedAdvanceDays(normalized)
                == storedValue else {
            throw PayloadError.invalidField("reminderAdvanceDaysRaw")
        }
        return normalized
    }

    private static func normalizedAliases(_ aliases: [String]) -> [String] {
        var seen = Set<String>()
        return aliases.compactMap { alias in
            let value = alias.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !value.isEmpty else { return nil }
            let key = value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { return nil }
            return value
        }
    }

    private static func uuid(
        _ rawValue: String,
        field: String
    ) throws -> UUID {
        guard let value = UUID(uuidString: rawValue) else {
            throw PayloadError.invalidField(field)
        }
        return value
    }

    private static func rawValue<Value: RawRepresentable>(
        _ type: Value.Type,
        _ rawValue: Value.RawValue,
        field: String
    ) throws -> Value {
        guard let value = Value(rawValue: rawValue) else {
            throw PayloadError.invalidField(field)
        }
        return value
    }

    private struct Values {
        let values: [String: SyncValue]

        init(_ values: [String: SyncValue]) {
            self.values = values
        }

        func string(_ key: String) throws -> String {
            guard let value = values[key] else {
                throw PayloadError.missingField(key)
            }
            guard case .string(let string) = value else {
                throw PayloadError.invalidField(key)
            }
            return string
        }

        func optionalString(_ key: String) throws -> String? {
            guard let value = values[key] else {
                throw PayloadError.missingField(key)
            }
            switch value {
            case .null:
                return nil
            case .string(let string):
                return string
            default:
                throw PayloadError.invalidField(key)
            }
        }

        func bool(_ key: String) throws -> Bool {
            guard let value = values[key] else {
                throw PayloadError.missingField(key)
            }
            guard case .bool(let bool) = value else {
                throw PayloadError.invalidField(key)
            }
            return bool
        }

        func integer(_ key: String, fallback: String? = nil) throws -> Int64 {
            if let value = values[key] {
                guard case .integer(let integer) = value else {
                    throw PayloadError.invalidField(key)
                }
                return integer
            }
            if let fallback {
                return try integer(fallback)
            }
            throw PayloadError.missingField(key)
        }

        func int(_ key: String) throws -> Int {
            let value = try integer(key)
            guard let exact = Int(exactly: value) else {
                throw PayloadError.invalidField(key)
            }
            return exact
        }

        func optionalInt(_ key: String) throws -> Int? {
            guard let value = values[key] else {
                throw PayloadError.missingField(key)
            }
            switch value {
            case .null:
                return nil
            case .integer(let integer):
                guard let exact = Int(exactly: integer) else {
                    throw PayloadError.invalidField(key)
                }
                return exact
            default:
                throw PayloadError.invalidField(key)
            }
        }

        func optionalInteger(_ key: String) throws -> Int64? {
            guard let value = values[key] else {
                throw PayloadError.missingField(key)
            }
            switch value {
            case .null:
                return nil
            case .integer(let integer):
                return integer
            default:
                throw PayloadError.invalidField(key)
            }
        }

        func optionalUUID(_ key: String) throws -> UUID? {
            guard let value = try optionalString(key) else { return nil }
            return try uuid(value, field: key)
        }

        func stringArray(_ key: String) throws -> [String] {
            guard let value = values[key] else {
                throw PayloadError.missingField(key)
            }
            guard case .array(let values) = value else {
                throw PayloadError.invalidField(key)
            }
            return try values.map { value in
                guard case .string(let string) = value else {
                    throw PayloadError.invalidField(key)
                }
                return string
            }
        }

        func date(_ key: String) throws -> Date {
            guard let value = values[key] else {
                throw PayloadError.missingField(key)
            }
            guard case .date(let date) = value else {
                throw PayloadError.invalidField(key)
            }
            return date
        }

        func optionalData(_ key: String) throws -> Data? {
            guard let value = values[key] else {
                throw PayloadError.missingField(key)
            }
            switch value {
            case .null:
                return nil
            case .data(let data):
                return data
            default:
                throw PayloadError.invalidField(key)
            }
        }
    }
}
