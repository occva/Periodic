import Foundation
import SwiftData

@ModelActor
actor TemplateCategoryStore {
    enum StoreError: LocalizedError {
        case emptyName
        case duplicateName
        case notFound
        case revisionConflict

        var errorDescription: String? {
            switch self {
            case .emptyName: "请输入分类名称。"
            case .duplicateName: "已经存在同名分类。"
            case .notFound: "这个分类已不存在。"
            case .revisionConflict: "这个分类已在别处修改，请刷新后重试。"
            }
        }
    }

    func fetchAll() throws -> [TemplateCategoryDTO] {
        let descriptor = FetchDescriptor<TemplateCategoryRecord>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map {
            TemplateCategoryDTO(id: $0.id, name: $0.name, revision: $0.revision)
        }
    }

    func save(_ input: TemplateCategoryInput) throws {
        do {
            try saveChanges(input)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func saveChanges(_ input: TemplateCategoryInput) throws {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError.emptyName }

        let categories = try modelContext.fetch(FetchDescriptor<TemplateCategoryRecord>())
        let normalizedName = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        guard !categories.contains(where: {
            $0.id != input.id
                && $0.name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ) == normalizedName
        }) else {
            throw StoreError.duplicateName
        }

        let normalizedInput = TemplateCategoryInput(
            id: input.id,
            expectedRevision: input.expectedRevision,
            name: name
        )
        if let category = categories.first(where: { $0.id == input.id }) {
            guard category.revision == input.expectedRevision else {
                throw StoreError.revisionConflict
            }
            category.apply(normalizedInput)
        } else {
            guard input.expectedRevision == nil else { throw StoreError.notFound }
            modelContext.insert(TemplateCategoryRecord(input: normalizedInput))
        }
        try modelContext.save()
    }

    func delete(id: UUID, expectedRevision: Int64) throws {
        do {
            try deleteChanges(id: id, expectedRevision: expectedRevision)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func deleteChanges(id: UUID, expectedRevision: Int64) throws {
        let categories = try modelContext.fetch(FetchDescriptor<TemplateCategoryRecord>())
        guard let category = categories.first(where: { $0.id == id }) else {
            throw StoreError.notFound
        }
        guard category.revision == expectedRevision else {
            throw StoreError.revisionConflict
        }

        let templates = try modelContext.fetch(FetchDescriptor<ServiceTemplateRecord>())
        for template in templates where template.customCategoryID == id {
            template.customCategoryID = nil
            template.categoryRaw = ServiceCategory.other.rawValue
            template.revision += 1
            template.updatedAt = Date()
        }
        modelContext.delete(category)
        try modelContext.save()
    }
}
