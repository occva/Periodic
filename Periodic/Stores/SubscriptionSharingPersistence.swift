import Foundation
import SwiftData

/// Used synchronously inside the owning Store actor's transaction and ModelContext.
struct SubscriptionSharingPersistence {
    enum Scope {
        case currentSubscriptions
        case subscription(UUID)
        case all
    }

    struct CurrentPlanLoadResult {
        let plansByOwnerKey: [String: SubscriptionSharingPlan]
        let invalidSubscriptionIDs: Set<UUID>
    }

    let context: ModelContext

    func plansByOwnerKey(in scope: Scope = .all) throws -> [String: SubscriptionSharingPlan] {
        let records = try records(in: scope)
        var plansByOwnerKey: [String: SubscriptionSharingPlan] = [:]
        for record in records {
            guard plansByOwnerKey[record.ownerKey] == nil else {
                throw SubscriptionSharingError.invalidStoredPlan
            }
            plansByOwnerKey[record.ownerKey] = try decode(record)
        }
        return plansByOwnerKey
    }

    func loadCurrentPlans() throws -> CurrentPlanLoadResult {
        let records = try records(in: .currentSubscriptions)
        let groupedRecords = Dictionary(grouping: records, by: \.ownerKey)
        var plansByOwnerKey: [String: SubscriptionSharingPlan] = [:]
        var invalidSubscriptionIDs: Set<UUID> = []

        for (ownerKey, ownerRecords) in groupedRecords {
            guard ownerRecords.count == 1, let record = ownerRecords.first else {
                for record in ownerRecords {
                    invalidSubscriptionIDs.formUnion(affectedSubscriptionIDs(for: record))
                }
                continue
            }
            do {
                plansByOwnerKey[ownerKey] = try decode(record)
            } catch {
                invalidSubscriptionIDs.formUnion(affectedSubscriptionIDs(for: record))
            }
        }

        return CurrentPlanLoadResult(
            plansByOwnerKey: plansByOwnerKey,
            invalidSubscriptionIDs: invalidSubscriptionIDs
        )
    }

    private func records(in scope: Scope) throws -> [SubscriptionSharingRecord] {
        let descriptor: FetchDescriptor<SubscriptionSharingRecord>
        switch scope {
        case .subscription(let subscriptionID):
            descriptor = FetchDescriptor(predicate: #Predicate { $0.subscriptionID == subscriptionID })
        case .currentSubscriptions:
            descriptor = FetchDescriptor(predicate: #Predicate { $0.periodID == nil })
        case .all:
            descriptor = FetchDescriptor()
        }
        return try context.fetch(descriptor)
    }

    func plan(subscriptionID: UUID, periodID: UUID? = nil) throws -> SubscriptionSharingPlan? {
        let key = SubscriptionSharingRecord.key(subscriptionID: subscriptionID, periodID: periodID)
        guard let record = try record(key: key) else { return nil }
        guard record.subscriptionID == subscriptionID else {
            throw SubscriptionSharingError.invalidStoredPlan
        }
        return try decode(record)
    }

    func set(
        _ plan: SubscriptionSharingPlan?,
        subscriptionID: UUID,
        periodID: UUID? = nil,
        myMoney: Money
    ) throws {
        let key = SubscriptionSharingRecord.key(subscriptionID: subscriptionID, periodID: periodID)
        let existing = try record(key: key)
        guard let plan else {
            if let existing { context.delete(existing) }
            return
        }
        try plan.validate(myMoney: myMoney)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(plan)
        if let existing {
            existing.subscriptionID = subscriptionID
            existing.periodID = periodID
            existing.planData = data
        } else {
            context.insert(SubscriptionSharingRecord(
                subscriptionID: subscriptionID,
                periodID: periodID,
                planData: data
            ))
        }
    }

    func delete(subscriptionIDs: Set<UUID>) throws {
        try context.fetch(FetchDescriptor<SubscriptionSharingRecord>())
            .filter { subscriptionIDs.contains($0.subscriptionID) }
            .forEach(context.delete)
    }

    private func record(key: String) throws -> SubscriptionSharingRecord? {
        var descriptor = FetchDescriptor<SubscriptionSharingRecord>(
            predicate: #Predicate { $0.ownerKey == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func decode(_ record: SubscriptionSharingRecord) throws -> SubscriptionSharingPlan {
        guard record.formatVersion == 1,
              record.ownerKey == SubscriptionSharingRecord.key(subscriptionID: record.subscriptionID, periodID: record.periodID) else {
            throw SubscriptionSharingError.invalidStoredPlan
        }
        return try JSONDecoder().decode(SubscriptionSharingPlan.self, from: record.planData)
    }

    private func affectedSubscriptionIDs(
        for record: SubscriptionSharingRecord
    ) -> Set<UUID> {
        var subscriptionIDs: Set<UUID> = [record.subscriptionID]
        if let ownerSubscriptionID = subscriptionID(fromCurrentOwnerKey: record.ownerKey) {
            subscriptionIDs.insert(ownerSubscriptionID)
        }
        return subscriptionIDs
    }

    private func subscriptionID(fromCurrentOwnerKey ownerKey: String) -> UUID? {
        let prefix = "subscription:"
        guard ownerKey.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(ownerKey.dropFirst(prefix.count)))
    }
}
