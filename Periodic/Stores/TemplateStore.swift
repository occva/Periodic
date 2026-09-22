import Foundation
import SwiftData

@ModelActor
actor TemplateStore {
    enum StoreError: LocalizedError {
        case notFound
        case revisionConflict
        case invalidStoredValue(String)

        var errorDescription: String? {
            switch self {
            case .notFound: "这条模板已不存在。"
            case .revisionConflict: "这条模板已在别处修改，请刷新后重试。"
            case .invalidStoredValue(let field): "模板数据的 \(field) 字段无法识别。"
            }
        }
    }

    func fetchAll() throws -> [ServiceTemplateDTO] {
        let descriptor = FetchDescriptor<ServiceTemplateRecord>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map(makeDTO)
    }

    func save(_ input: ServiceTemplateInput) throws {
        do {
            let aliases = normalizedAliases(input.aliases)
            let aliasesData = try JSONEncoder().encode(aliases)
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
