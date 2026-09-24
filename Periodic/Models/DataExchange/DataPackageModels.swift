import Foundation

struct DataPackageManifest: Codable, Equatable, Sendable {
    static let currentFormat = "periodic-data-package"
    static let currentVersion = 1

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
        let templates: Int
        let categories: Int
        let builtinCategoryAssignments: Int
    }
}

struct DataPackageSnapshot: Codable, Equatable, Sendable {
    var subscriptions: [DataPackageSubscription]
    var periods: [DataPackagePeriod]
    var templates: [DataPackageTemplate]
    var categories: [DataPackageCategory]
    var builtinCategoryAssignments: [DataPackageBuiltinCategoryAssignment]
    var settings: DataPackageSettings?

    static let empty = DataPackageSnapshot(
        subscriptions: [],
        periods: [],
        templates: [],
        categories: [],
        builtinCategoryAssignments: [],
        settings: nil
    )
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
    let automaticallyRenews: Bool
    let revision: Int64
    let createdAt: Date
    let updatedAt: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
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
            && lhs.automaticallyRenews == rhs.automaticallyRenews
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
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
    let templates: Int
    let categories: Int
    let assignments: Int
}

struct DataImportPreview: Equatable, Sendable {
    let subscriptions: EntityChanges
    let periods: EntityChanges
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
        subscriptions.additions + periods.additions + templates.additions
            + categories.additions + assignments.additions
    }

    var totalConflicts: Int {
        subscriptions.conflicts + periods.conflicts + templates.conflicts
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
