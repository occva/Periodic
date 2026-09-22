import Foundation

enum TemplateSource: String, CaseIterable, Identifiable, Sendable {
    case all
    case builtin
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppLocalization.string("全部")
        case .builtin: AppLocalization.string("内置")
        case .user: AppLocalization.string("我的模板")
        }
    }
}

enum TemplateKey: Hashable, Sendable {
    case builtin(String)
    case user(UUID)

    var stableID: String {
        switch self {
        case .builtin(let key): key
        case .user(let id): "user.\(id.uuidString)"
        }
    }
}

struct ServiceTemplateDTO: Identifiable, Hashable, Sendable {
    var id: String { key.stableID }
    let key: TemplateKey
    let source: TemplateSource
    let name: String
    let aliases: [String]
    let category: ServiceCategory
    let customCategoryID: UUID?
    let symbolName: String
    let iconResourceName: String?
    let iconURLString: String?
    let suggestedBillingKind: BillingKind
    let suggestedCycleMonths: Int?
    let suggestedMoney: Money?
    let currency: CurrencyCode
    let revision: Int64?

    var subscriptionPreset: SubscriptionTemplatePreset {
        SubscriptionTemplatePreset(
            name: name,
            symbolName: symbolName,
            iconResourceName: iconResourceName,
            iconURLString: iconURLString,
            category: category,
            billingKind: suggestedBillingKind,
            cycleMonths: suggestedCycleMonths,
            money: suggestedMoney,
            currency: currency
        )
    }
}

struct SubscriptionTemplatePreset: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let symbolName: String
    let iconResourceName: String?
    let iconURLString: String?
    let category: ServiceCategory
    let billingKind: BillingKind
    let cycleMonths: Int?
    let money: Money?
    let currency: CurrencyCode
}

struct ServiceTemplateInput: Sendable {
    let id: UUID
    let expectedRevision: Int64?
    let name: String
    let aliases: [String]
    let category: ServiceCategory
    let customCategoryID: UUID?
    let symbolName: String
    let iconResourceName: String?
    let iconURLString: String?
    let suggestedBillingKind: BillingKind
    let suggestedCycleMonths: Int?
    let suggestedMoney: Money?
    let currency: CurrencyCode
}

struct BuiltinServiceCatalog: Decodable, Sendable {
    let catalogVersion: String
    let entries: [Entry]

    struct Entry: Decodable, Sendable {
        let key: String
        let name: String
        let aliases: [String]
        let category: ServiceCategory
        let symbolName: String
        let iconResourceName: String?
        let suggestedBillingKind: BillingKind
        let suggestedCycleMonths: Int?
        let currency: CurrencyCode

        var dto: ServiceTemplateDTO {
            ServiceTemplateDTO(
                key: .builtin(key),
                source: .builtin,
                name: name,
                aliases: aliases,
                category: category,
                customCategoryID: nil,
                symbolName: symbolName,
                iconResourceName: iconResourceName,
                iconURLString: nil,
                suggestedBillingKind: suggestedBillingKind,
                suggestedCycleMonths: suggestedCycleMonths,
                suggestedMoney: nil,
                currency: currency,
                revision: nil
            )
        }
    }
}

struct TemplateCategoryDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let revision: Int64
}

struct TemplateCategoryInput: Sendable {
    let id: UUID
    let expectedRevision: Int64?
    let name: String
}

struct AppleIconSearchResult: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let artistName: String
    let artworkURL: URL
}
