import Foundation
import SwiftData

/// Used synchronously inside the owning Store actor's transaction and ModelContext.
struct SubscriptionSharingPersistence {
    enum Scope {
        case currentSubscriptions
        case subscription(UUID)
        case all
    }

    let context: ModelContext

    func plansByOwnerKey(in scope: Scope = .all) throws -> [String: SubscriptionSharingPlan] {
        let descriptor: FetchDescriptor<SubscriptionSharingRecord>
        switch scope {
        case .subscription(let subscriptionID):
            descriptor = FetchDescriptor(predicate: #Predicate { $0.subscriptionID == subscriptionID })
        case .currentSubscriptions:
            descriptor = FetchDescriptor(predicate: #Predicate { $0.periodID == nil })
        case .all:
            descriptor = FetchDescriptor()
        }
        let records = try context.fetch(descriptor)
        return try Dictionary(uniqueKeysWithValues: records.map { record in
            (record.ownerKey, try decode(record))
        })
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

    func remove(subscriptionID: UUID, periodID: UUID? = nil) throws {
        let key = SubscriptionSharingRecord.key(
            subscriptionID: subscriptionID,
            periodID: periodID
        )
        if let record = try record(key: key) {
            context.delete(record)
        }
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
}
