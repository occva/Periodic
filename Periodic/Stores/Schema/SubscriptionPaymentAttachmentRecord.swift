import Foundation
import SwiftData

@Model
final class SubscriptionPaymentAttachmentRecord {
    // V4 migration source. New writes use SubscriptionPaymentAttachmentItemRecord.
    @Attribute(.unique) var paymentID: UUID
    var reference: String

    init(paymentID: UUID, reference: String) {
        self.paymentID = paymentID
        self.reference = reference
    }
}
