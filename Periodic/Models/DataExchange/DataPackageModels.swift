import Foundation

struct DataPackageManifest: Codable, Equatable, Sendable {
    static let currentFormat = "periodic-data-package"
    static let currentVersion = 5

    let format: String
    let formatVersion: Int
    let minimumReaderVersion: Int
    let exportID: UUID
    let sourceDatasetID: UUID
    let createdAt: Date
    let appVersion: String
    let calendar: String
    let scope: String
    let tables: TableCounts
    let assetCount: Int
    let includesSettings: Bool

    struct TableCounts: Codable, Equatable, Sendable {
        let subscriptions: Int
        let periods: Int
        let payments: Int?
        let templates: Int
        let categories: Int
        let builtinCategoryAssignments: Int

        init(
            subscriptions: Int,
            periods: Int,
            payments: Int? = nil,
            templates: Int,
            categories: Int,
            builtinCategoryAssignments: Int
        ) {
            self.subscriptions = subscriptions
            self.periods = periods
            self.payments = payments
            self.templates = templates
            self.categories = categories
            self.builtinCategoryAssignments = builtinCategoryAssignments
        }
    }
}

struct DataPackageSnapshot: Codable, Equatable, Sendable {
    var subscriptions: [DataPackageSubscription]
    var periods: [DataPackagePeriod]
    var payments: [DataPackagePayment]
    var templates: [DataPackageTemplate]
    var categories: [DataPackageCategory]
    var builtinCategoryAssignments: [DataPackageBuiltinCategoryAssignment]
    var settings: DataPackageSettings?

    init(
        subscriptions: [DataPackageSubscription],
        periods: [DataPackagePeriod],
        payments: [DataPackagePayment] = [],
        templates: [DataPackageTemplate],
        categories: [DataPackageCategory],
        builtinCategoryAssignments: [DataPackageBuiltinCategoryAssignment],
        settings: DataPackageSettings?
    ) {
        self.subscriptions = subscriptions
        self.periods = periods
        self.payments = payments
        self.templates = templates
        self.categories = categories
        self.builtinCategoryAssignments = builtinCategoryAssignments
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case subscriptions
        case periods
        case payments
        case templates
        case categories
        case builtinCategoryAssignments
        case settings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try container.decode([DataPackageSubscription].self, forKey: .subscriptions)
        periods = try container.decode([DataPackagePeriod].self, forKey: .periods)
        payments = try container.decodeIfPresent([DataPackagePayment].self, forKey: .payments) ?? []
        templates = try container.decode([DataPackageTemplate].self, forKey: .templates)
        categories = try container.decode([DataPackageCategory].self, forKey: .categories)
        builtinCategoryAssignments = try container.decode(
            [DataPackageBuiltinCategoryAssignment].self,
            forKey: .builtinCategoryAssignments
        )
        settings = try container.decodeIfPresent(DataPackageSettings.self, forKey: .settings)
    }

    static let empty = DataPackageSnapshot(
        subscriptions: [],
        periods: [],
        payments: [],
        templates: [],
        categories: [],
        builtinCategoryAssignments: [],
        settings: nil
    )
}

struct DataPackagePayment: Codable, Equatable, Sendable, Identifiable {
    let recordVersion: Int
    let id: UUID
    let subscriptionID: UUID
    let periodRecordID: UUID?
    let kind: SubscriptionPaymentKind
    let paymentDate: LocalDate
    let amountMinor: Int64
    let currency: CurrencyCode
    let currencyScale: Int
    let periodStart: LocalDate?
    let periodEnd: LocalDate?
    let note: String
    var attachmentAssetIDs: [String]
    let revision: Int64
    let createdAt: Date
    let updatedAt: Date

    init(
        recordVersion: Int,
        id: UUID,
        subscriptionID: UUID,
        periodRecordID: UUID?,
        kind: SubscriptionPaymentKind,
        paymentDate: LocalDate,
        amountMinor: Int64,
        currency: CurrencyCode,
        currencyScale: Int,
        periodStart: LocalDate?,
        periodEnd: LocalDate?,
        note: String,
        attachmentAssetIDs: [String],
        revision: Int64,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.recordVersion = recordVersion
        self.id = id
        self.subscriptionID = subscriptionID
        self.periodRecordID = periodRecordID
        self.kind = kind
        self.paymentDate = paymentDate
        self.amountMinor = amountMinor
        self.currency = currency
        self.currencyScale = currencyScale
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.note = note
        self.attachmentAssetIDs = attachmentAssetIDs
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case recordVersion
        case id
        case subscriptionID
        case periodRecordID
        case kind
        case paymentDate
        case amountMinor
        case currency
        case currencyScale
        case periodStart
        case periodEnd
        case note
        case attachmentAssetIDs
        case attachmentAssetID
        case revision
        case createdAt
        case updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordVersion = try container.decode(Int.self, forKey: .recordVersion)
        id = try container.decode(UUID.self, forKey: .id)
        subscriptionID = try container.decode(UUID.self, forKey: .subscriptionID)
        periodRecordID = try container.decodeIfPresent(UUID.self, forKey: .periodRecordID)
        kind = try container.decode(SubscriptionPaymentKind.self, forKey: .kind)
        paymentDate = try container.decode(LocalDate.self, forKey: .paymentDate)
        amountMinor = try container.decode(Int64.self, forKey: .amountMinor)
        currency = try container.decode(CurrencyCode.self, forKey: .currency)
        currencyScale = try container.decode(Int.self, forKey: .currencyScale)
        periodStart = try container.decodeIfPresent(LocalDate.self, forKey: .periodStart)
        periodEnd = try container.decodeIfPresent(LocalDate.self, forKey: .periodEnd)
        note = try container.decode(String.self, forKey: .note)
        if let values = try container.decodeIfPresent(
            [String].self,
            forKey: .attachmentAssetIDs
        ) {
            attachmentAssetIDs = values
        } else {
            attachmentAssetIDs = try container.decodeIfPresent(
                String.self,
                forKey: .attachmentAssetID
            ).map { [$0] } ?? []
        }
        revision = try container.decode(Int64.self, forKey: .revision)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recordVersion, forKey: .recordVersion)
        try container.encode(id, forKey: .id)
        try container.encode(subscriptionID, forKey: .subscriptionID)
        try container.encodeIfPresent(periodRecordID, forKey: .periodRecordID)
        try container.encode(kind, forKey: .kind)
        try container.encode(paymentDate, forKey: .paymentDate)
        try container.encode(amountMinor, forKey: .amountMinor)
        try container.encode(currency, forKey: .currency)
        try container.encode(currencyScale, forKey: .currencyScale)
        try container.encodeIfPresent(periodStart, forKey: .periodStart)
        try container.encodeIfPresent(periodEnd, forKey: .periodEnd)
        try container.encode(note, forKey: .note)
        try container.encode(attachmentAssetIDs, forKey: .attachmentAssetIDs)
        try container.encode(revision, forKey: .revision)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.subscriptionID == rhs.subscriptionID
            && lhs.periodRecordID == rhs.periodRecordID
            && lhs.kind == rhs.kind
            && lhs.paymentDate == rhs.paymentDate
            && lhs.amountMinor == rhs.amountMinor
            && lhs.currency == rhs.currency
            && lhs.currencyScale == rhs.currencyScale
            && lhs.periodStart == rhs.periodStart
            && lhs.periodEnd == rhs.periodEnd
            && lhs.note == rhs.note
            && lhs.attachmentAssetIDs == rhs.attachmentAssetIDs
    }
}

struct DataPackageSubscription: Codable, Equatable, Sendable, Identifiable {
    let recordVersion: Int
    let id: UUID
    let name: String
    let symbolName: String
    let iconResourceName: String?
    var iconAssetID: String?
    let category: ServiceCategory
    let managementState: ManagementState
    let billingKind: BillingKind
    let periodStart: LocalDate?
    let expiry: LocalDate?
    let cycleMonths: Int?
    let amountMinor: Int64
    let currency: CurrencyCode
    let currencyScale: Int
    let note: String
    let reminderEnabled: Bool
    let reminderAdvanceDays: [Int]?
    let reminderMinuteOfDay: Int?
    let automaticallyRenews: Bool
    let revision: Int64
    let createdAt: Date
    let updatedAt: Date
    var sharing: SubscriptionSharingPlan? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sharing == rhs.sharing
            && lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.symbolName == rhs.symbolName
            && lhs.iconResourceName == rhs.iconResourceName
            && lhs.iconAssetID == rhs.iconAssetID
            && lhs.category == rhs.category
            && lhs.managementState == rhs.managementState
            && lhs.billingKind == rhs.billingKind
            && lhs.periodStart == rhs.periodStart
            && lhs.expiry == rhs.expiry
            && lhs.cycleMonths == rhs.cycleMonths
            && lhs.amountMinor == rhs.amountMinor
            && lhs.currency == rhs.currency
            && lhs.currencyScale == rhs.currencyScale
            && lhs.note == rhs.note
            && lhs.reminderEnabled == rhs.reminderEnabled
            && lhs.normalizedReminderAdvanceDays == rhs.normalizedReminderAdvanceDays
            && lhs.normalizedReminderMinuteOfDay == rhs.normalizedReminderMinuteOfDay
            && lhs.automaticallyRenews == rhs.automaticallyRenews
    }

    private var normalizedReminderAdvanceDays: [Int] {
        SubscriptionNotificationSchedule.normalizedAdvanceDays(
            reminderAdvanceDays ?? SubscriptionNotificationSchedule.defaultAdvanceDays
        )
    }

    private var normalizedReminderMinuteOfDay: Int {
        reminderMinuteOfDay ?? SubscriptionNotificationSchedule.defaultMinuteOfDay
    }
}

struct DataPackagePeriod: Codable, Equatable, Sendable, Identifiable {
    let recordVersion: Int
    let id: UUID
    let subscriptionID: UUID
    let billingKind: BillingKind
    let cycleMonths: Int?
    let start: LocalDate
    let end: LocalDate?
    let amountMinor: Int64
    let currency: CurrencyCode
    let currencyScale: Int
    let source: SubscriptionPeriodSource
    let createdAt: Date
    var sharing: SubscriptionSharingPlan? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sharing == rhs.sharing
            && lhs.id == rhs.id
            && lhs.subscriptionID == rhs.subscriptionID
            && lhs.billingKind == rhs.billingKind
            && lhs.cycleMonths == rhs.cycleMonths
            && lhs.start == rhs.start
            && lhs.end == rhs.end
            && lhs.amountMinor == rhs.amountMinor
            && lhs.currency == rhs.currency
            && lhs.currencyScale == rhs.currencyScale
            && lhs.source == rhs.source
    }
}

struct DataPackageTemplate: Codable, Equatable, Sendable, Identifiable {
    let recordVersion: Int
    let id: UUID
    let name: String
    let aliases: [String]
    let category: ServiceCategory
    let customCategoryID: UUID?
    let symbolName: String
    let iconResourceName: String?
    var iconAssetID: String?
    let suggestedBillingKind: BillingKind
    let suggestedCycleMonths: Int?
    let suggestedAmountMinor: Int64?
    let currency: CurrencyCode
    let currencyScale: Int
    let revision: Int64
    let createdAt: Date
    let updatedAt: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.aliases == rhs.aliases
            && lhs.category == rhs.category
            && lhs.customCategoryID == rhs.customCategoryID
            && lhs.symbolName == rhs.symbolName
            && lhs.iconResourceName == rhs.iconResourceName
            && lhs.iconAssetID == rhs.iconAssetID
            && lhs.suggestedBillingKind == rhs.suggestedBillingKind
            && lhs.suggestedCycleMonths == rhs.suggestedCycleMonths
            && lhs.suggestedAmountMinor == rhs.suggestedAmountMinor
            && lhs.currency == rhs.currency
            && lhs.currencyScale == rhs.currencyScale
    }
}

struct DataPackageCategory: Codable, Equatable, Sendable, Identifiable {
    let recordVersion: Int
    let id: UUID
    let name: String
    let revision: Int64
    let createdAt: Date
    let updatedAt: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

struct DataPackageBuiltinCategoryAssignment: Codable, Equatable, Sendable, Identifiable {
    var id: String { templateKey }

    let recordVersion: Int
    let templateKey: String
    let category: ServiceCategory
    let customCategoryID: UUID?
    let updatedAt: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.templateKey == rhs.templateKey
            && lhs.category == rhs.category
            && lhs.customCategoryID == rhs.customCategoryID
    }
}

struct DataPackageSettings: Codable, Equatable, Sendable {
    let appearance: String?
    let language: String?
    let defaultCurrency: String?
    let selectedCurrencies: String?
    let usesCurrencySymbols: Bool
    let menuBarEnabled: Bool
    let menuBarDueHorizon: Int
    let menuBarShowsForecasts: Bool
    let exchangeRateBaseCurrency: String?

    init(
        appearance: String?,
        language: String?,
        defaultCurrency: String?,
        selectedCurrencies: String?,
        usesCurrencySymbols: Bool,
        menuBarEnabled: Bool,
        menuBarDueHorizon: Int,
        menuBarShowsForecasts: Bool,
        exchangeRateBaseCurrency: String?
    ) {
        self.appearance = appearance
        self.language = language
        self.defaultCurrency = defaultCurrency
        self.selectedCurrencies = selectedCurrencies
        self.usesCurrencySymbols = usesCurrencySymbols
        self.menuBarEnabled = menuBarEnabled
        self.menuBarDueHorizon = menuBarDueHorizon
        self.menuBarShowsForecasts = menuBarShowsForecasts
        self.exchangeRateBaseCurrency = exchangeRateBaseCurrency
    }
}

struct EncodedDataPackage: Sendable {
    let files: [String: Data]
    let preferredFilename: String
}

struct DecodedDataPackage: Sendable {
    let manifest: DataPackageManifest
    let snapshot: DataPackageSnapshot
    let assets: [String: Data]
    let sourceDigest: String
}

struct DataExportPreview: Equatable, Sendable {
    let subscriptions: Int
    let periods: Int
    let payments: Int
    let templates: Int
    let categories: Int
    let assignments: Int
}

struct DataImportPreview: Equatable, Sendable {
    let subscriptions: EntityChanges
    let periods: EntityChanges
    let payments: EntityChanges
    let templates: EntityChanges
    let categories: EntityChanges
    let assignments: EntityChanges
    let assetCount: Int

    struct EntityChanges: Equatable, Sendable {
        let additions: Int
        let conflicts: Int
        let unchanged: Int
    }

    var totalAdditions: Int {
        subscriptions.additions + periods.additions + payments.additions + templates.additions
            + categories.additions + assignments.additions
    }

    var totalConflicts: Int {
        subscriptions.conflicts + periods.conflicts + payments.conflicts + templates.conflicts
            + categories.conflicts + assignments.conflicts
    }
}

enum DataImportConflictResolution: String, CaseIterable, Identifiable, Sendable {
    case keepLocal
    case useImported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepLocal: AppLocalization.string("保留本地记录")
        case .useImported: AppLocalization.string("使用导入记录")
        }
    }
}

struct DataImportPlan: Sendable {
    let id: UUID
    let package: DecodedDataPackage
    let targetDigest: String
    let preview: DataImportPreview
    let expiresAt: Date
}

struct DataImportReceipt: Equatable, Sendable {
    let added: Int
    let updated: Int
    let skipped: Int
}

enum DataExchangeError: LocalizedError {
    case storeUnavailable
    case invalidPackage(String)
    case unsupportedVersion(Int)
    case checksumMismatch(String)
    case resourceLimitExceeded
    case invalidRecord(String)
    case stalePlan
    case planExpired

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            AppLocalization.string("数据存储尚未就绪。")
        case .invalidPackage(let detail):
            String(
                format: AppLocalization.string("所选文件不是有效的 Periodic 数据包：%@"),
                AppLocalization.string(detail)
            )
        case .unsupportedVersion(let version):
            String(format: AppLocalization.string("数据包版本 %d 暂不受支持。"), version)
        case .checksumMismatch(let path):
            String(format: AppLocalization.string("数据包中的 %@ 已损坏或被修改。"), path)
        case .resourceLimitExceeded:
            AppLocalization.string("数据包超过安全大小或记录数量限制。")
        case .invalidRecord(let detail):
            String(
                format: AppLocalization.string("数据包记录无效：%@"),
                AppLocalization.string(detail)
            )
        case .stalePlan:
            AppLocalization.string("预览后本地数据已发生变化，请重新选择文件并预览。")
        case .planExpired:
            AppLocalization.string("导入预览已过期，请重新选择文件。")
        }
    }
}
