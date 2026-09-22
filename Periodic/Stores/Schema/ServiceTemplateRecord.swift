import Foundation
import SwiftData

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
