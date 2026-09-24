import Foundation
import Observation
import UserNotifications

struct SubscriptionNotificationPlan: Equatable, Sendable {
    static let identifierPrefix = "periodic.renewal."
    static let expiryIdentifierPrefix = "periodic.expiry."
    static let capacityBudget = 64

    let identifier: String
    let subscriptionID: UUID
    let subscriptionName: String
    let kind: Kind
    let deliveryComponents: DateComponents

    enum Kind: Equatable, Sendable {
        case expiryReminder
        case renewalConfirmation
    }

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
                  let expiry = subscription.expiry,
                  expiry >= referenceDate else {
                return nil
            }
            guard let kind = notificationKind(for: subscription) else { return nil }
            return identifier(
                subscriptionID: subscription.id,
                expiry: expiry,
                kind: kind
            )
        })
    }

    static func staleManagedIdentifiers(
        in identifiers: [String],
        activeIdentifiers: Set<String>
    ) -> [String] {
        identifiers.filter {
            ($0.hasPrefix(identifierPrefix) || $0.hasPrefix(expiryIdentifierPrefix))
                && !activeIdentifiers.contains($0)
        }
    }

    static func plans(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [SubscriptionNotificationPlan] {
        subscriptions.compactMap { subscription in
            guard subscription.managementState == .active,
                  subscription.billingKind == .recurring,
                  let expiry = subscription.expiry,
                  expiry >= referenceDate else {
                return nil
            }
            guard let kind = notificationKind(for: subscription) else { return nil }
            var components = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day],
                from: expiry.date(calendar: calendar)
            )
            components.hour = 9
            components.minute = 0
            guard let deliveryDate = calendar.date(from: components), deliveryDate > now else {
                return nil
            }
            return SubscriptionNotificationPlan(
                identifier: identifier(
                    subscriptionID: subscription.id,
                    expiry: expiry,
                    kind: kind
                ),
                subscriptionID: subscription.id,
                subscriptionName: subscription.name,
                kind: kind,
                deliveryComponents: components
            )
        }
        .sorted {
            let left = ($0.deliveryComponents.date ?? .distantFuture, $0.identifier)
            let right = ($1.deliveryComponents.date ?? .distantFuture, $1.identifier)
            return left < right
        }
    }

    static func prioritizedPlans(
        _ plans: [SubscriptionNotificationPlan],
        capacity: Int = capacityBudget
    ) -> [SubscriptionNotificationPlan] {
        Array(plans.prefix(max(0, capacity)))
    }

    private static func notificationKind(for subscription: SubscriptionDTO) -> Kind? {
        if subscription.automaticallyRenews {
            return .renewalConfirmation
        }
        return subscription.reminderEnabled ? .expiryReminder : nil
    }

    private static func identifier(
        subscriptionID: UUID,
        expiry: LocalDate,
        kind: Kind
    ) -> String {
        let prefix = switch kind {
        case .expiryReminder: expiryIdentifierPrefix
        case .renewalConfirmation: identifierPrefix
        }
        return prefix + subscriptionID.uuidString + "." + String(expiry.dayNumber)
    }
}

enum SubscriptionNotificationStatus: Equatable, Sendable {
    case idle
    case ready(scheduledCount: Int, deferredCount: Int, failedCount: Int)
    case noReminders
    case denied
    case failed
}

@MainActor
@Observable
final class SubscriptionNotificationService {
    private let center: UNUserNotificationCenter
    private let isSystemIntegrationEnabled: Bool
    let selection: SubscriptionNotificationSelection
    private let notificationDelegate: SubscriptionNotificationDelegate
    private var reconciliationTask: Task<Void, Never>?
    private var reconciliationSequence = 0
    private(set) var status = SubscriptionNotificationStatus.idle

    init(
        center: UNUserNotificationCenter = .current(),
        isSystemIntegrationEnabled: Bool = true
    ) {
        self.center = center
        self.isSystemIntegrationEnabled = isSystemIntegrationEnabled
        let selection = SubscriptionNotificationSelection()
        self.selection = selection
        notificationDelegate = SubscriptionNotificationDelegate(selection: selection)
        if isSystemIntegrationEnabled {
            center.delegate = notificationDelegate
        }
    }

    func reconcile(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate = .today
    ) async {
        reconciliationSequence &+= 1
        let sequence = reconciliationSequence
        let previousTask = reconciliationTask
        let task = Task { @MainActor [weak self] in
            await previousTask?.value
            guard let self else { return }
            await performReconciliation(
                subscriptions: subscriptions,
                referenceDate: referenceDate
            )
        }
        reconciliationTask = task
        await task.value
        if sequence == reconciliationSequence {
            reconciliationTask = nil
        }
    }

    private func performReconciliation(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate
    ) async {
        guard isSystemIntegrationEnabled else {
            status = .idle
            return
        }
        let candidatePlans = SubscriptionNotificationPlan.plans(
            subscriptions: subscriptions,
            referenceDate: referenceDate
        )
        let plans = SubscriptionNotificationPlan.prioritizedPlans(candidatePlans)
        let deferredCount = candidatePlans.count - plans.count
        let scheduledIdentifiers = Set(plans.map(\.identifier))
        let candidateIdentifiers = Set(candidatePlans.map(\.identifier))
        let activeIdentifiers = SubscriptionNotificationPlan.activeIdentifiers(
            subscriptions: subscriptions,
            referenceDate: referenceDate
        )
        let pendingIdentifiersToKeep = scheduledIdentifiers.union(
            activeIdentifiers.subtracting(candidateIdentifiers)
        )
        do {
            let pending = await center.pendingNotificationRequests()
            let stalePendingIdentifiers = SubscriptionNotificationPlan.staleManagedIdentifiers(
                in: pending.map(\.identifier),
                activeIdentifiers: pendingIdentifiersToKeep
            )
            center.removePendingNotificationRequests(withIdentifiers: stalePendingIdentifiers)

            let delivered = await center.deliveredNotifications()
            let staleDeliveredIdentifiers = SubscriptionNotificationPlan.staleManagedIdentifiers(
                in: delivered.map(\.request.identifier),
                activeIdentifiers: activeIdentifiers
            )
            center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIdentifiers)

            guard !activeIdentifiers.isEmpty else {
                status = .noReminders
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
                switch plan.kind {
                case .expiryReminder:
                    content.title = AppLocalization.string("订阅今天到期")
                    content.body = String(
                        format: AppLocalization.string("%@ 今天到期，请及时处理。"),
                        plan.subscriptionName
                    )
                case .renewalConfirmation:
                    content.title = AppLocalization.string("确认订阅续费")
                    content.body = String(
                        format: AppLocalization.string("%@ 今天到期，请确认服务商是否已自动续费。"),
                        plan.subscriptionName
                    )
                }
                content.sound = .default
                content.userInfo = ["subscriptionID": plan.subscriptionID.uuidString]
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: plan.deliveryComponents,
                    repeats: false
                )
                do {
                    try await center.add(
                        UNNotificationRequest(
                            identifier: plan.identifier,
                            content: content,
                            trigger: trigger
                        )
                    )
                } catch {
                    AppLog.lifecycle.error("Failed to schedule a subscription notification")
                }
            }
            let reconciledPending = await center.pendingNotificationRequests()
            let reconciledIdentifiers = Set(reconciledPending.map(\.identifier))
            let scheduledCount = scheduledIdentifiers.intersection(reconciledIdentifiers).count
            status = .ready(
                scheduledCount: scheduledCount,
                deferredCount: deferredCount,
                failedCount: plans.count - scheduledCount
            )
        } catch {
            status = .failed
            AppLog.lifecycle.error("Failed to reconcile subscription notifications")
        }
    }
}

@MainActor
@Observable
final class SubscriptionNotificationSelection {
    private(set) var subscriptionID: UUID?

    func select(_ id: UUID) {
        subscriptionID = id
    }

    func consume() -> UUID? {
        defer { subscriptionID = nil }
        return subscriptionID
    }
}

private final class SubscriptionNotificationDelegate: NSObject,
    UNUserNotificationCenterDelegate
{
    private let selection: SubscriptionNotificationSelection

    init(selection: SubscriptionNotificationSelection) {
        self.selection = selection
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let value = response.notification.request.content.userInfo["subscriptionID"] as? String,
              let id = UUID(uuidString: value) else {
            return
        }
        await selection.select(id)
    }
}
