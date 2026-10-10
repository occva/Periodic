import Foundation

struct DataImportCategoryNames: Sendable {
    let categories: [DataPackageCategory]
    private let unknownOverrideIDs: Set<UUID>

    init(
        local: [DataPackageCategory],
        imported: [DataPackageCategory],
        conflictResolution: DataImportConflictResolution,
        overrides: [UUID: String] = [:]
    ) {
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for incoming in imported where merged[incoming.id] == nil || conflictResolution == .useImported {
            merged[incoming.id] = incoming
        }
        unknownOverrideIDs = Set(overrides.keys).subtracting(merged.keys)
        categories = merged.values.map { category in
            guard let name = overrides[category.id] else { return category }
            return category.renamed(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var duplicateIDs: Set<UUID> {
        let groups = Dictionary(grouping: categories) { TemplateCategoryName.normalized($0.name) }
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }

    var unresolvedIDs: Set<UUID> {
        duplicateIDs.union(categories.filter {
            TemplateCategoryName.normalized($0.name).isEmpty
        }.map(\.id))
    }

    var hasUnresolvedNames: Bool {
        !unknownOverrideIDs.isEmpty || !unresolvedIDs.isEmpty
    }

    func validatedCategories() throws -> [DataPackageCategory] {
        guard !hasUnresolvedNames else {
            throw DataExchangeError.invalidRecord(AppLocalization.string(
                "请在导入预览中为分类设置非空且互不重复的名称。"
            ))
        }
        return categories
    }
}
