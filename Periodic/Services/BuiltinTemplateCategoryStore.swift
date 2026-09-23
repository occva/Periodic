import Foundation
import SwiftData

@ModelActor
actor BuiltinTemplateCategoryStore {
    enum StoreError: LocalizedError {
        case invalidStoredValue

        var errorDescription: String? {
            "已保存的内置模板分类设置无法读取。"
        }
    }

    func fetchAssignments() throws -> [String: TemplateCategoryAssignment] {
        let records = try modelContext.fetch(
            FetchDescriptor<BuiltinTemplateCategoryAssignmentRecord>()
        )
        var assignments: [String: TemplateCategoryAssignment] = [:]
        for record in records {
            if let customCategoryID = record.customCategoryID {
                assignments[record.templateKey] = .custom(customCategoryID)
            } else if let category = ServiceCategory(rawValue: record.categoryRaw) {
                assignments[record.templateKey] = .builtin(category)
            } else {
                throw StoreError.invalidStoredValue
            }
        }
        return assignments
    }

    func assign(_ assignment: TemplateCategoryAssignment, toBuiltinTemplate key: String) throws {
        do {
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
