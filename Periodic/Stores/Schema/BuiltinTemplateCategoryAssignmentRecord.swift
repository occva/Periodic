import Foundation
import SwiftData

@Model
final class BuiltinTemplateCategoryAssignmentRecord {
    @Attribute(.unique) var templateKey: String
    var categoryRaw: String
    var customCategoryID: UUID?
    var updatedAt: Date

    init(
        templateKey: String,
        assignment: TemplateCategoryAssignment,
        now: Date = Date()
    ) {
        self.templateKey = templateKey
        categoryRaw = assignment.category.rawValue
        customCategoryID = assignment.customCategoryID
        updatedAt = now
    }

    func apply(_ assignment: TemplateCategoryAssignment, now: Date = Date()) {
        categoryRaw = assignment.category.rawValue
        customCategoryID = assignment.customCategoryID
        updatedAt = now
    }
}
