import Foundation
import SwiftData

@ModelActor
actor TemplateStore {
    enum StoreError: LocalizedError {
        case notFound
        case categoryNotFound
        case revisionConflict
        case invalidStoredValue(String)

        var errorDescription: String? {
            switch self {
            case .notFound: "这条模板已不存在。"
            case .categoryNotFound: "所选模板分类已不存在，请重新选择。"
            case .revisionConflict: "这条模板已在别处修改，请刷新后重试。"
            case .invalidStoredValue(let field): "模板数据的 \(field) 字段无法识别。"
            }
        }
    }

    func fetchAll() throws -> [ServiceTemplateDTO] {
        let descriptor = FetchDescriptor<ServiceTemplateRecord>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        let records = try modelContext.fetch(descriptor)
        let referencedCategoryIDs = Set(records.compactMap(\.customCategoryID))
        let validCategoryIDs: Set<UUID>
        if referencedCategoryIDs.isEmpty {
            validCategoryIDs = []
        } else {
            validCategoryIDs = Set(
                try modelContext.fetch(FetchDescriptor<TemplateCategoryRecord>()).map(\.id)
            )
        }

        var templates: [ServiceTemplateDTO] = []
        var firstConversionError: (any Error)?
        for record in records {
            do {
                let template = try makeDTO(record)
                if let categoryID = template.customCategoryID,
                   !validCategoryIDs.contains(categoryID) {
                    templates.append(template.assigningCategory(.builtin(.other)))
                    AppLog.persistence.warning("Recovered a template with a missing custom category")
                } else {
                    templates.append(template)
                }
            } catch {
                firstConversionError = firstConversionError ?? error
            }
        }
        if templates.isEmpty, !records.isEmpty, let firstConversionError {
            throw firstConversionError
        }
        if firstConversionError != nil {
            AppLog.persistence.warning("Skipped invalid user template records while loading")
        }
        return templates
    }

    func save(_ input: ServiceTemplateInput) throws {
        do {
            let aliases = normalizedAliases(input.aliases)
            let aliasesData = try JSONEncoder().encode(aliases)
            if let categoryID = input.customCategoryID {
                var categoryDescriptor = FetchDescriptor<TemplateCategoryRecord>(
                    predicate: #Predicate { $0.id == categoryID }
                )
                categoryDescriptor.fetchLimit = 1
                let categoryExists = try !modelContext.fetch(categoryDescriptor).isEmpty
                guard categoryExists else {
                    throw StoreError.categoryNotFound
                }
            }
            let records = try modelContext.fetch(FetchDescriptor<ServiceTemplateRecord>())

            if let record = records.first(where: { $0.id == input.id }) {
                guard let expectedRevision = input.expectedRevision,
                      record.revision == expectedRevision else {
                    throw StoreError.revisionConflict
                }
                record.apply(input, aliasesData: aliasesData)
            } else {
                guard input.expectedRevision == nil else { throw StoreError.notFound }
                modelContext.insert(ServiceTemplateRecord(input: input, aliasesData: aliasesData))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func delete(id: UUID, expectedRevision: Int64) throws {
        do {
            let records = try modelContext.fetch(FetchDescriptor<ServiceTemplateRecord>())
            guard let record = records.first(where: { $0.id == id }) else {
                throw StoreError.notFound
            }
            guard record.revision == expectedRevision else {
                throw StoreError.revisionConflict
            }
            modelContext.delete(record)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func makeDTO(_ record: ServiceTemplateRecord) throws -> ServiceTemplateDTO {
        guard let category = ServiceCategory(rawValue: record.categoryRaw) else {
            throw StoreError.invalidStoredValue("categoryRaw")
        }
        guard let billingKind = BillingKind(rawValue: record.suggestedBillingKindRaw) else {
            throw StoreError.invalidStoredValue("suggestedBillingKindRaw")
        }
        guard let currency = CurrencyCode(rawValue: record.currencyCode),
              currency.scale == record.currencyScale else {
            throw StoreError.invalidStoredValue("currencyCode")
        }
        let aliases = try JSONDecoder().decode([String].self, from: record.aliasesData)
        let money = record.suggestedAmountMinor.map { Money(minorUnits: $0, currency: currency) }
        return ServiceTemplateDTO(
            key: .user(record.id),
            source: .user,
            name: record.name,
            aliases: aliases,
            category: category,
            customCategoryID: record.customCategoryID,
            symbolName: record.symbolName,
            iconResourceName: record.iconResourceName,
            iconURLString: record.iconURLString,
            suggestedBillingKind: billingKind,
            suggestedCycleMonths: record.suggestedCycleMonths,
            suggestedMoney: money,
            currency: currency,
            revision: record.revision
        )
    }

    private func normalizedAliases(_ aliases: [String]) -> [String] {
        var seen = Set<String>()
        return aliases.compactMap { alias in
            let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return value
        }
    }
}
