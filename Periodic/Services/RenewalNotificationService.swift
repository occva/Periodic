import Foundation
import Observation
import UserNotifications

struct RenewalNotificationPlan: Equatable, Sendable {
    static let identifierPrefix = "periodic.renewal."

    let identifier: String
    let subscriptionName: String
    let deliveryComponents: DateComponents

    static func identifier(subscriptionID: UUID, expiry: LocalDate) -> String {
        identifierPrefix + subscriptionID.uuidString + "." + String(expiry.dayNumber)
    }

    static func activeIdentifiers(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate
    ) -> Set<String> {
        Set(subscriptions.compactMap { subscription in
            guard subscription.managementState == .active,
                  subscription.billingKind == .recurring,
                  subscription.automaticallyRenews,
                  let expiry = subscription.expiry,
                  expiry >= referenceDate else {
                return nil
            }
            return identifier(subscriptionID: subscription.id, expiry: expiry)
        })
    }

    static func staleManagedIdentifiers(
        in identifiers: [String],
        activeIdentifiers: Set<String>
    ) -> [String] {
        identifiers.filter {
            $0.hasPrefix(identifierPrefix) && !activeIdentifiers.contains($0)
        }
    }

    static func plans(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [RenewalNotificationPlan] {
        subscriptions.compactMap { subscription in
            guard subscription.managementState == .active,
                  subscription.billingKind == .recurring,
                  subscription.automaticallyRenews,
                  let expiry = subscription.expiry,
                  expiry >= referenceDate else {
                return nil
            }
            var components = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day],
                from: expiry.date(calendar: calendar)
            )
            components.hour = 9
            components.minute = 0
            guard let deliveryDate = calendar.date(from: components), deliveryDate > now else {
                return nil
            }
            return RenewalNotificationPlan(
                identifier: identifier(subscriptionID: subscription.id, expiry: expiry),
                subscriptionName: subscription.name,
                deliveryComponents: components
            )
        }
    }
}

enum RenewalNotificationStatus: Equatable, Sendable {
    case idle
    case ready(scheduledCount: Int)
    case noAutomaticRenewals
    case denied
    case failed
}

@MainActor
@Observable
final class RenewalNotificationService {
    private let center: UNUserNotificationCenter
    private(set) var status = RenewalNotificationStatus.idle

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func reconcile(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate = .today
    ) async {
        let plans = RenewalNotificationPlan.plans(
            subscriptions: subscriptions,
            referenceDate: referenceDate
        )
        let activeIdentifiers = RenewalNotificationPlan.activeIdentifiers(
            subscriptions: subscriptions,
            referenceDate: referenceDate
        )
        do {
            let pending = await center.pendingNotificationRequests()
            let stalePendingIdentifiers = RenewalNotificationPlan.staleManagedIdentifiers(
                in: pending.map(\.identifier),
                activeIdentifiers: activeIdentifiers
            )
            center.removePendingNotificationRequests(withIdentifiers: stalePendingIdentifiers)

            let delivered = await center.deliveredNotifications()
            let staleDeliveredIdentifiers = RenewalNotificationPlan.staleManagedIdentifiers(
                in: delivered.map(\.request.identifier),
                activeIdentifiers: activeIdentifiers
            )
            center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIdentifiers)

            guard !activeIdentifiers.isEmpty else {
                status = .noAutomaticRenewals
                return
            }

            let settings = await center.notificationSettings()
            var isAuthorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined, !plans.isEmpty {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
            }
            guard isAuthorized else {
                status = .denied
                return
            }

            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = "确认订阅续费"
                content.body = "\(plan.subscriptionName) 今天到期，请确认服务商是否已自动续费。"
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: plan.deliveryComponents,
                    repeats: false
                )
                try await center.add(
                    UNNotificationRequest(
                        identifier: plan.identifier,
                        content: content,
                        trigger: trigger
                    )
                )
            }
            status = .ready(scheduledCount: plans.count)
        } catch {
            status = .failed
            AppLog.lifecycle.error("Failed to reconcile renewal notifications")
        }
    }
}
