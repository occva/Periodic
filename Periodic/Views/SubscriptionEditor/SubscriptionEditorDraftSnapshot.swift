import Foundation

struct SubscriptionEditorDraftSnapshot: Equatable {
    let name: String
    let iconResourceName: String?
    let iconURLString: String?
    let category: ServiceCategory
    let managementState: ManagementState
    let billingKind: BillingKind
    let billingCycle: BillingCycle
    let sharing: SubscriptionSharingDraft
    let amountText: String
    let currency: CurrencyCode
    let hasStartDate: Bool
    let startDate: LocalDate
    let hasExpiryDate: Bool
    let expiryDate: LocalDate
    let reminderEnabled: Bool
    let reminderTiming: SubscriptionReminderTiming
    let customReminderDate: LocalDate
    let customReminderFollowsExpiry: Bool
    let reminderMinuteOfDay: Int
    let isReminderScheduleModified: Bool
    let automaticallyRenews: Bool
    let note: String
}
