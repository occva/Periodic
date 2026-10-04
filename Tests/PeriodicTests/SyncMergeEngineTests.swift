import Foundation
import Testing
@testable import Periodic

struct SyncMergeEngineTests {
    @Test func mergesDifferentFieldsFromTheSameBaseRevision() {
        let local = change(
            fields: ["name": .string("Local name")]
        )
        let remote = change(
            fields: ["note": .string("Remote note")]
        )

        let outcome = SyncMergeEngine.merge(local: local, remote: remote)

        guard case .merged(let merged) = outcome else {
            Issue.record("不同字段应自动合并")
            return
        }
        #expect(merged.fieldValues["name"] == .string("Local name"))
        #expect(merged.fieldValues["note"] == .string("Remote note"))
        #expect(merged.targetRevision == 3)
    }

    @Test func reportsDifferentValuesForTheSameField() {
        let local = change(fields: ["name": .string("Local")])
        let remote = change(fields: ["name": .string("Remote")])

        let outcome = SyncMergeEngine.merge(local: local, remote: remote)

        guard case .conflict(let conflict) = outcome else {
            Issue.record("同字段不同值必须产生冲突")
            return
        }
        #expect(conflict.reasons.contains(.fields(["name"])))
    }

    @Test func reportsDeleteVersusModification() {
        let local = change(
            operation: .delete,
            fields: [:]
        )
        let remote = change(fields: ["note": .string("Edited offline")])

        let outcome = SyncMergeEngine.merge(local: local, remote: remote)

        guard case .conflict(let conflict) = outcome else {
            Issue.record("删除与旧版本修改必须产生冲突")
            return
        }
        #expect(conflict.reasons.contains(.deletionVersusModification))
    }

    @Test func treatsMoneyFieldsAsAnAtomicGroup() {
        let local = change(fields: ["periodAmountMinor": .integer(1_200)])
        let remote = change(fields: ["currencyCode": .string("USD")])

        let outcome = SyncMergeEngine.merge(local: local, remote: remote)

        guard case .conflict(let conflict) = outcome else {
            Issue.record("金额和币种交叉修改必须产生冲突")
            return
        }
        #expect(
            conflict.reasons.contains(
                .atomicFieldGroup([
                    "periodAmountMinor",
                    "currencyCode",
                    "currencyScale",
                ])
            )
        )
    }

    @Test func treatsBillingKindAndCycleAsAnAtomicGroup() {
        let local = change(fields: ["billingKindRaw": .string("lifetime")])
        let remote = change(fields: ["cycleMonths": .integer(12)])

        let outcome = SyncMergeEngine.merge(local: local, remote: remote)

        guard case .conflict(let conflict) = outcome else {
            Issue.record("计费类型和周期交叉修改必须产生冲突")
            return
        }
        #expect(
            conflict.reasons.contains(
                .atomicFieldGroup(["billingKindRaw", "cycleMonths"])
            )
        )
    }

    @Test func acceptsTheSameValueForAnOverlappingField() {
        let local = change(fields: ["name": .string("Periodic")])
        let remote = change(fields: ["name": .string("Periodic")])

        let outcome = SyncMergeEngine.merge(local: local, remote: remote)

        guard case .merged(let merged) = outcome else {
            Issue.record("相同字段写入相同值不应要求人工处理")
            return
        }
        #expect(merged.fieldValues == ["name": .string("Periodic")])
    }

    @Test func reportsDifferentContentForTheSameAssetID() {
        let local = change(
            recordType: .iconAsset,
            fields: ["contentHash": .string(String(repeating: "a", count: 64))]
        )
        let remote = change(
            recordType: .iconAsset,
            fields: ["contentHash": .string(String(repeating: "b", count: 64))]
        )

        let outcome = SyncMergeEngine.merge(local: local, remote: remote)

        guard case .conflict(let conflict) = outcome else {
            Issue.record("同一图片记录的不同内容必须产生冲突")
            return
        }
        #expect(conflict.reasons.contains(.fields(["contentHash"])))
    }

    private func change(
        recordType: SyncRecordType = .subscription,
        operation: SyncMutationOperation = .update,
        fields: [String: SyncValue]
    ) -> SyncChangeSet {
        SyncChangeSet(
            recordType: recordType,
            recordID: "subscription",
            baseRevision: 1,
            targetRevision: 2,
            operation: operation,
            fieldValues: fields,
            relationshipChanges: []
        )
    }
}
