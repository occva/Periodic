import Foundation
import SwiftData

@Model
final class TemplateCategoryRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var revision: Int64
    var createdAt: Date
    var updatedAt: Date

    init(input: TemplateCategoryInput, now: Date = Date()) {
        id = input.id
        name = input.name
        revision = 1
        createdAt = now
        updatedAt = now
    }

    func apply(_ input: TemplateCategoryInput, now: Date = Date()) {
        name = input.name
        revision += 1
        updatedAt = now
    }
}
