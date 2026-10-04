import Foundation
import SwiftData

/// A subscription owns its current plan; a period owns an independent historical snapshot.
/// Keeping this additive entity preserves the schemas and records of existing stores.
@Model
final class SubscriptionSharingRecord {
    @Attribute(.unique) var ownerKey: String
    var subscriptionID: UUID
    var periodID: UUID?
    var formatVersion: Int
    var planData: Data

    init(subscriptionID: UUID, periodID: UUID?, planData: Data) {
        ownerKey = Self.key(subscriptionID: subscriptionID, periodID: periodID)
        self.subscriptionID = subscriptionID
        self.periodID = periodID
        formatVersion = 1
        self.planData = planData
    }

    static func key(subscriptionID: UUID, periodID: UUID? = nil) -> String {
        if let periodID { return "period:" + periodID.uuidString }
        return "subscription:" + subscriptionID.uuidString
    }
}
