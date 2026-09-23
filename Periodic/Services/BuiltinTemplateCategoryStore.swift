import Foundation
import SwiftData

@ModelActor
actor BuiltinTemplateCategoryStore {
    enum StoreError: LocalizedError {
        case categoryNotFound

        var errorDescription: String? {
            "所选模板分类已不存在，请重新选择。"
        }
    }

    func fetchAssignments() throws -> [String: TemplateCategoryAssignment] {
        let records = try modelContext.fetch(
            FetchDescriptor<BuiltinTemplateCategoryAssignmentRecord>()
        )
        var assignments: [String: TemplateCategoryAssignment] = [:]
        let referencedCategoryIDs = Set(records.compactMap(\.customCategoryID))
        let validCategoryIDs: Set<UUID>
        if referencedCategoryIDs.isEmpty {
            validCategoryIDs = []
        } else {
            validCategoryIDs = Set(
                try modelContext.fetch(FetchDescriptor<TemplateCategoryRecord>()).map(\.id)
            )
        }
        for record in records {
            if let customCategoryID = record.customCategoryID {
                if validCategoryIDs.contains(customCategoryID) {
                    assignments[record.templateKey] = .custom(customCategoryID)
                } else {
                    assignments[record.templateKey] = .builtin(.other)
                    AppLog.persistence.warning(
                        "Recovered a built-in template assignment with a missing custom category"
                    )
                }
            } else if let category = ServiceCategory(rawValue: record.categoryRaw) {
                assignments[record.templateKey] = .builtin(category)
            } else {
                AppLog.persistence.warning(
                    "Skipped an invalid built-in template category assignment"
                )
            }
        }
        return assignments
    }

    func assign(_ assignment: TemplateCategoryAssignment, toBuiltinTemplate key: String) throws {
        do {
            if let categoryID = assignment.customCategoryID {
                var categoryDescriptor = FetchDescriptor<TemplateCategoryRecord>(
                    predicate: #Predicate { $0.id == categoryID }
                )
                categoryDescriptor.fetchLimit = 1
                let categoryExists = try !modelContext.fetch(categoryDescriptor).isEmpty
                guard categoryExists else {
                    throw StoreError.categoryNotFound
                }
            }
            let records = try modelContext.fetch(
                FetchDescriptor<BuiltinTemplateCategoryAssignmentRecord>()
            )
            if let record = records.first(where: { $0.templateKey == key }) {
                record.apply(assignment)
            } else {
                modelContext.insert(
                    BuiltinTemplateCategoryAssignmentRecord(
                        templateKey: key,
                        assignment: assignment
                    )
                )
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
