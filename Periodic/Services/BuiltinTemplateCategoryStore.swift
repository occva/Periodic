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

    func assign(
        _ assignment: TemplateCategoryAssignment,
        toBuiltinTemplate key: String
    ) async throws {
        let lease = try await datasetAccess.acquireWrite()
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
                let previous = SyncRecordPayload.builtinCategoryAssignment(record)
                record.apply(assignment)
                try SyncMutationJournal.recordUpdate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .builtinTemplateCategoryAssignment,
                    recordID: record.templateKey,
                    previous: previous,
                    current: SyncRecordPayload.builtinCategoryAssignment(record)
                )
            } else {
                let record = BuiltinTemplateCategoryAssignmentRecord(
                    templateKey: key,
                    assignment: assignment
                )
                modelContext.insert(record)
                try SyncMutationJournal.recordCreate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: .builtinTemplateCategoryAssignment,
                    recordID: record.templateKey,
                    fieldValues: SyncRecordPayload.builtinCategoryAssignment(
                        record
                    )
                )
            }
            try DatasetMetadata.advanceRevision(
                in: modelContext,
                descriptor: datasetAccess.descriptor
            )
            try modelContext.save()
            await datasetAccess.releaseWrite(lease)
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }
}
