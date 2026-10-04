import Foundation
import Testing
@testable import Periodic

struct SyncUploadBatchBuilderTests {
    @Test func coalescesContiguousMutationsIntoOneFullUploadRecord() throws {
        let recordID = UUID().uuidString
        let firstID = UUID()
        let secondID = UUID()
        let mutations = [
            mutation(
                id: firstID,
                recordID: recordID,
                baseRevision: 0,
                targetRevision: 1,
                operation: .create,
                fields: ["name": .string("Periodic")]
            ),
            mutation(
                id: secondID,
                recordID: recordID,
                baseRevision: 1,
                targetRevision: 2,
                operation: .update,
                fields: ["note": .string("Edited")]
            ),
        ]
        let snapshot = snapshot(
            recordID: recordID,
            revision: 2,
            fields: [
                "name": .string("Periodic"),
                "note": .string("Edited"),
            ]
        )

        let uploads = try SyncUploadBatchBuilder.build(
            mutations: mutations,
            snapshots: [snapshot]
        )

        let upload = try #require(uploads.first)
        #expect(uploads.count == 1)
        #expect(upload.baseRevision == 0)
        #expect(upload.changedFields == ["name", "note"])
        #expect(upload.mutationIDs == [firstID, secondID])
        #expect(upload.snapshot.fieldValues == snapshot.fieldValues)
    }

    @Test func rejectsAGapInTheLocalRevisionChain() {
        let recordID = UUID().uuidString
        let mutations = [
            mutation(
                recordID: recordID,
                baseRevision: 0,
                targetRevision: 1,
                operation: .create,
                fields: ["name": .string("Periodic")]
            ),
            mutation(
                recordID: recordID,
                baseRevision: 2,
                targetRevision: 3,
                operation: .update,
                fields: ["note": .string("Gap")]
            ),
        ]

        #expect(throws: SyncUploadBatchBuilder.BuildError.nonContiguousRevision) {
            try SyncUploadBatchBuilder.build(
                mutations: mutations,
                snapshots: [
                    snapshot(
                        recordID: recordID,
                        revision: 3,
                        fields: ["name": .string("Periodic")]
                    ),
                ]
            )
        }
    }

    @Test func deletionUploadDoesNotExposeEarlierChangedFields() throws {
        let recordID = UUID().uuidString
        let createID = UUID()
        let deleteID = UUID()
        let uploads = try SyncUploadBatchBuilder.build(
            mutations: [
                mutation(
                    id: createID,
                    recordID: recordID,
                    baseRevision: 0,
                    targetRevision: 1,
                    operation: .create,
                    fields: ["name": .string("Transient")]
                ),
                mutation(
                    id: deleteID,
                    recordID: recordID,
                    baseRevision: 1,
                    targetRevision: 2,
                    operation: .delete,
                    fields: [:]
                ),
            ],
            snapshots: [
                snapshot(
                    recordID: recordID,
                    revision: 2,
                    fields: [:],
                    isDeleted: true
                ),
            ]
        )

        let upload = try #require(uploads.first)
        #expect(upload.changedFields.isEmpty)
        #expect(upload.relationshipChanges.isEmpty)
        #expect(upload.mutationIDs == [createID, deleteID])
    }

    private func mutation(
        id: UUID = UUID(),
        recordID: String,
        baseRevision: Int64,
        targetRevision: Int64,
        operation: SyncMutationOperation,
        fields: [String: SyncValue]
    ) -> SyncMutation {
        SyncMutation(
            mutationID: id,
            recordType: .subscription,
            recordID: recordID,
            baseRevision: baseRevision,
            targetRevision: targetRevision,
            operation: operation,
            state: .pending,
            fieldValues: fields,
            relationshipChanges: [],
            deviceID: UUID(),
            createdAt: Date(timeIntervalSince1970: Double(targetRevision))
        )
    }

    private func snapshot(
        recordID: String,
        revision: Int64,
        fields: [String: SyncValue],
        isDeleted: Bool = false
    ) -> SyncRecordSnapshot {
        SyncRecordSnapshot(
            recordType: .subscription,
            recordID: recordID,
            revision: revision,
            modifiedAt: Date(),
            modifiedByDeviceID: UUID(),
            isDeleted: isDeleted,
            deletedAt: isDeleted ? Date() : nil,
            fieldValues: fields,
            serverRecordData: nil
        )
    }
}
