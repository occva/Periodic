import Foundation
import SwiftData

@Model
final class SubscriptionPaymentAttachmentItemRecord {
    @Attribute(.unique) var id: UUID
    var paymentID: UUID
    var reference: String
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        paymentID: UUID,
        reference: String,
        sortOrder: Int
    ) {
        self.id = id
        self.paymentID = paymentID
        self.reference = reference
        self.sortOrder = sortOrder
    }
}
