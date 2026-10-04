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

    private var datasetAccess = DatasetAccessCoordinator()

    init(
        modelContainer: ModelContainer,
        datasetAccess: DatasetAccessCoordinator = DatasetAccessCoordinator()
    ) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.datasetAccess = datasetAccess
    }

    func fetchAll() throws -> [TemplateCategoryDTO] {
        let descriptor = FetchDescriptor<TemplateCategoryRecord>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map {
            TemplateCategoryDTO(id: $0.id, name: $0.name, revision: $0.revision)
        }
    }

    func save(_ input: TemplateCategoryInput) async throws {
        let lease = try await datasetAccess.acquireWrite()
        do {
            try saveChanges(input)
            await datasetAccess.releaseWrite(lease)
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
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
            let previous = SyncRecordPayload.category(category)
            category.apply(normalizedInput)
            try SyncMutationJournal.recordUpdate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .templateCategory,
                recordID: category.id.uuidString,
                previous: previous,
                current: SyncRecordPayload.category(category),
                legacyBaseRevision: input.expectedRevision ?? category.revision - 1
            )
        } else {
            guard input.expectedRevision == nil else { throw StoreError.notFound }
            let category = TemplateCategoryRecord(input: normalizedInput)
            modelContext.insert(category)
            try SyncMutationJournal.recordCreate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .templateCategory,
                recordID: category.id.uuidString,
                fieldValues: SyncRecordPayload.category(category)
            )
        }
        try DatasetMetadata.advanceRevision(
            in: modelContext,
            descriptor: datasetAccess.descriptor
        )
        try modelContext.save()
    }

    func delete(id: UUID, expectedRevision: Int64) async throws {
        let lease = try await datasetAccess.acquireWrite()
        do {
            try deleteChanges(id: id, expectedRevision: expectedRevision)
            await datasetAccess.releaseWrite(lease)
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
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
            let previous = try SyncRecordPayload.template(template)
            let baseRevision = template.revision
            template.customCategoryID = nil
            template.categoryRaw = ServiceCategory.other.rawValue
            template.revision += 1
            template.updatedAt = Date()
            try SyncMutationJournal.recordUpdate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .serviceTemplate,
                recordID: template.id.uuidString,
                previous: previous,
                current: try SyncRecordPayload.template(template),
                legacyBaseRevision: baseRevision
            )
        }

        let builtinAssignments = try modelContext.fetch(
            FetchDescriptor<BuiltinTemplateCategoryAssignmentRecord>()
        )
        for assignment in builtinAssignments where assignment.customCategoryID == id {
            let previous = SyncRecordPayload.builtinCategoryAssignment(assignment)
            assignment.apply(.builtin(.other))
            try SyncMutationJournal.recordUpdate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: .builtinTemplateCategoryAssignment,
                recordID: assignment.templateKey,
                previous: previous,
                current: SyncRecordPayload.builtinCategoryAssignment(assignment)
            )
        }
        try SyncMutationJournal.recordDelete(
            in: modelContext,
            deviceID: datasetAccess.deviceID,
            recordType: .templateCategory,
            recordID: category.id.uuidString,
            legacyBaseRevision: expectedRevision
        )
        modelContext.delete(category)
        try DatasetMetadata.advanceRevision(
            in: modelContext,
            descriptor: datasetAccess.descriptor
        )
        try modelContext.save()
    }
}
