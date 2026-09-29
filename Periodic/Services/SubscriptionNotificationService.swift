import Foundation
import Observation
import UserNotifications

struct SubscriptionNotificationPlan: Equatable, Sendable {
    static let requestFingerprintUserInfoKey = "requestFingerprint"

    struct Namespace: Equatable, Sendable {
        static let production = Namespace(prefix: "periodic.")
        static let sample = Namespace(prefix: "periodic.sample.")

        let renewalIdentifierPrefix: String
        let expiryIdentifierPrefix: String

        init(prefix: String) {
            renewalIdentifierPrefix = prefix + "renewal."
            expiryIdentifierPrefix = prefix + "expiry."
        }

        func contains(_ identifier: String) -> Bool {
            identifier.hasPrefix(renewalIdentifierPrefix)
                || identifier.hasPrefix(expiryIdentifierPrefix)
        }
    }

    static let identifierPrefix = Namespace.production.renewalIdentifierPrefix
    static let expiryIdentifierPrefix = Namespace.production.expiryIdentifierPrefix
    static let capacityBudget = 64

    let identifier: String
    let subscriptionID: UUID
    let subscriptionName: String
    let kind: Kind
    let expiry: LocalDate
    let advanceDays: Int
    let remainingDays: Int
    let deliveryComponents: DateComponents
    let scheduledDeliveryDate: Date
    let isCatchUp: Bool

    enum Kind: Equatable, Sendable {
        case expiryReminder
        case renewalConfirmation
    }

    var submissionFingerprint: String {
        [
            identifier,
            String(deliveryComponents.year ?? 0),
            String(deliveryComponents.month ?? 0),
            String(deliveryComponents.day ?? 0),
            String(deliveryComponents.hour ?? 0),
            String(deliveryComponents.minute ?? 0),
            deliveryComponents.timeZone?.identifier ?? "",
        ].joined(separator: "|")
    }

    var requestFingerprint: String {
        [
            submissionFingerprint,
            kind.fingerprintValue,
            subscriptionName,
            expiry.iso8601Text,
            AppLocalization.activeLanguageIdentifier,
        ].joined(separator: "|")
    }

    var legacySubmissionFingerprint: String {
        [
            identifier,
            String(deliveryComponents.year ?? 0),
            String(deliveryComponents.month ?? 0),
            String(deliveryComponents.day ?? 0),
            String(deliveryComponents.hour ?? 0),
            String(deliveryComponents.minute ?? 0),
            subscriptionName,
        ].joined(separator: "|")
    }

    static func identifier(
        subscriptionID: UUID,
        expiry: LocalDate,
        namespace: Namespace = .production
    ) -> String {
        namespace.renewalIdentifierPrefix
            + subscriptionID.uuidString
            + "."
            + String(expiry.dayNumber)
    }

    static func activeIdentifiers(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate,
        namespace: Namespace = .production
    ) -> Set<String> {
        return Set(subscriptions.flatMap { subscription in
            notificationSeeds(for: subscription).compactMap { seed in
                guard let expiry = subscription.expiry,
                      expiry >= referenceDate else { return nil }
                return identifier(
                    subscriptionID: subscription.id,
                    expiry: expiry,
                    advanceDays: seed.advanceDays,
                    kind: seed.kind,
                    namespace: namespace
                )
            }
        })
    }

    static func staleManagedIdentifiers(
        in identifiers: [String],
        activeIdentifiers: Set<String>,
        namespace: Namespace = .production,
        obsoleteNamespaces: [Namespace] = []
    ) -> [String] {
        identifiers.filter { identifier in
            obsoleteNamespaces.contains { $0.contains(identifier) }
                || (namespace.contains(identifier) && !activeIdentifiers.contains(identifier))
        }
    }

    static func plans(
        subscriptions: [SubscriptionDTO],
        referenceDate: LocalDate,
        calendar: Calendar = .current,
        now: Date = Date(),
        namespace: Namespace = .production
    ) -> [SubscriptionNotificationPlan] {
        return subscriptions.flatMap { subscription -> [SubscriptionNotificationPlan] in
            let hour = subscription.reminderMinuteOfDay / 60
            let minute = subscription.reminderMinuteOfDay % 60
            return notificationSeeds(for: subscription).compactMap {
                seed -> SubscriptionNotificationPlan? in
                guard let expiry = subscription.expiry,
                      let deliveryDay = expiry.addingDays(-seed.advanceDays),
                      expiry >= referenceDate else { return nil }
                var components = calendar.dateComponents(
                    [.calendar, .timeZone, .year, .month, .day],
                    from: deliveryDay.date(calendar: calendar)
                )
                components.hour = hour
                components.minute = minute
                guard let deliveryDate = calendar.date(from: components) else { return nil }
                return SubscriptionNotificationPlan(
                    identifier: identifier(
                        subscriptionID: subscription.id,
                        expiry: expiry,
                        advanceDays: seed.advanceDays,
                        kind: seed.kind,
                        namespace: namespace
                    ),
                    subscriptionID: subscription.id,
                    subscriptionName: subscription.name,
                    kind: seed.kind,
                    expiry: expiry,
                    advanceDays: seed.advanceDays,
                    remainingDays: expiry.dayNumber - referenceDate.dayNumber,
                    deliveryComponents: components,
                    scheduledDeliveryDate: deliveryDate,
                    isCatchUp: deliveryDate <= now
                )
            }
        }
        .sorted {
            let left = ($0.scheduledDeliveryDate, $0.identifier)
            let right = ($1.scheduledDeliveryDate, $1.identifier)
            return left < right
        }
    }

    static func plansRequiringSubmission(
        _ plans: [SubscriptionNotificationPlan],
        observedIdentifiers: Set<String>,
        wasSubmitted: (SubscriptionNotificationPlan) -> Bool
    ) -> [SubscriptionNotificationPlan] {
        let futurePlans = plans.filter { plan in
            !plan.isCatchUp
                && (!observedIdentifiers.contains(plan.identifier) || !wasSubmitted(plan))
        }
        let catchUpPlans = latestCatchUpPlans(in: plans).filter { plan in
            !observedIdentifiers.contains(plan.identifier) && !wasSubmitted(plan)
        }
        return (futurePlans + catchUpPlans).sorted {
            let left = ($0.scheduledDeliveryDate, $0.identifier)
            let right = ($1.scheduledDeliveryDate, $1.identifier)
            return left < right
        }
    }

    static func latestCatchUpPlans(
        in plans: [SubscriptionNotificationPlan]
    ) -> [SubscriptionNotificationPlan] {
        Dictionary(
            grouping: plans.filter(\.isCatchUp),
            by: \.subscriptionID
        ).values.compactMap { plans in
            plans.max { $0.scheduledDeliveryDate < $1.scheduledDeliveryDate }
        }
    }

    static func prioritizedPlans(
        _ plans: [SubscriptionNotificationPlan],
        capacity: Int = capacityBudget
    ) -> [SubscriptionNotificationPlan] {
        Array(plans.prefix(max(0, capacity)))
    }

    static func reconciliationSelection(
        from plans: [SubscriptionNotificationPlan],
        currentPendingIdentifiers: Set<String>,
        observedIdentifiers: Set<String>,
        reservedPendingCount: Int,
        capacity: Int = capacityBudget,
        wasSubmitted: (SubscriptionNotificationPlan) -> Bool
    ) -> SubscriptionNotificationReconciliationSelection {
        let candidates = plansRequiringSubmission(
            plans,
            observedIdentifiers: observedIdentifiers,
            wasSubmitted: wasSubmitted
        )
        let currentPendingPlans = plans.filter {
            currentPendingIdentifiers.contains($0.identifier)
        }
        let eligiblePlans = Dictionary(
            (currentPendingPlans + candidates).map { ($0.identifier, $0) },
            uniquingKeysWith: { current, _ in current }
        ).values.sorted {
            let left = ($0.scheduledDeliveryDate, $0.identifier)
            let right = ($1.scheduledDeliveryDate, $1.identifier)
            return left < right
        }
        let availableCapacity = max(0, capacity - max(0, reservedPendingCount))
        let selectedPlans = prioritizedPlans(
            eligiblePlans,
            capacity: availableCapacity
        )
        let selectedIdentifiers = Set(selectedPlans.map(\.identifier))
        let candidateIdentifiers = Set(candidates.map(\.identifier))
        return SubscriptionNotificationReconciliationSelection(
            plansToSubmit: selectedPlans.filter {
                candidateIdentifiers.contains($0.identifier)
                    && !currentPendingIdentifiers.contains($0.identifier)
            },
            pendingIdentifiersToKeep: selectedIdentifiers.intersection(
                currentPendingIdentifiers
            ),
            expectedFutureIdentifiers: Set(
                selectedPlans.filter { !$0.isCatchUp }.map(\.identifier)
            ),
            deferredCount: eligiblePlans.count - selectedPlans.count
        )
    }

    private static func notificationSeeds(
        for subscription: SubscriptionDTO
    ) -> [(kind: Kind, advanceDays: Int)] {
        guard subscription.managementState == .active,
              subscription.billingKind == .recurring,
              subscription.expiry != nil else { return [] }
        var seeds: [(Kind, Int)] = []
        if subscription.automaticallyRenews {
            seeds.append((.renewalConfirmation, 0))
        } else if subscription.reminderEnabled {
            seeds.append(contentsOf: subscription.reminderAdvanceDays.map {
                (.expiryReminder, $0)
            })
        }
        return seeds
    }

    private static func identifier(
        subscriptionID: UUID,
        expiry: LocalDate,
        advanceDays: Int,
        kind: Kind,
        namespace: Namespace
    ) -> String {
        let prefix = switch kind {
        case .expiryReminder: namespace.expiryIdentifierPrefix
        case .renewalConfirmation: namespace.renewalIdentifierPrefix
        }
        let base = prefix + subscriptionID.uuidString + "." + String(expiry.dayNumber)
        return advanceDays == 0 ? base : base + ".advance." + String(advanceDays)
    }
}

struct SubscriptionNotificationReconciliationSelection: Equatable, Sendable {
    let plansToSubmit: [SubscriptionNotificationPlan]
    let pendingIdentifiersToKeep: Set<String>
    let expectedFutureIdentifiers: Set<String>
    let deferredCount: Int
}

private extension SubscriptionNotificationPlan.Kind {
    var fingerprintValue: String {
        switch self {
        case .expiryReminder: "expiry"
        case .renewalConfirmation: "renewal"
        }
    }
}

enum SubscriptionNotificationStatus: Equatable, Sendable {
    case idle
    case authorizationRequired
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
    private let namespace: SubscriptionNotificationPlan.Namespace
    private let obsoleteNamespaces: [SubscriptionNotificationPlan.Namespace]
    let selection: SubscriptionNotificationSelection
    private let notificationDelegate: SubscriptionNotificationDelegate
    private let submissionHistory: SubscriptionNotificationSubmissionHistory
    private var reconciliationTask: Task<Void, Never>?
    private var reconciliationSequence = 0
    private(set) var status = SubscriptionNotificationStatus.idle

    init(
        center: UNUserNotificationCenter = .current(),
        isSystemIntegrationEnabled: Bool = true,
        defaults: UserDefaults = .standard,
        submissionHistoryKey: String = PreferenceKey.submittedNotificationRequests,
        namespace: SubscriptionNotificationPlan.Namespace = .production,
        obsoleteNamespaces: [SubscriptionNotificationPlan.Namespace] = []
    ) {
        self.center = center
        self.isSystemIntegrationEnabled = isSystemIntegrationEnabled
        self.namespace = namespace
        self.obsoleteNamespaces = obsoleteNamespaces
        let selection = SubscriptionNotificationSelection()
        let submissionHistory = SubscriptionNotificationSubmissionHistory(
            defaults: defaults,
            key: submissionHistoryKey
        )
        self.selection = selection
        self.submissionHistory = submissionHistory
        notificationDelegate = SubscriptionNotificationDelegate(
            selection: selection,
            submissionHistory: submissionHistory
        )
        if isSystemIntegrationEnabled {
            center.delegate = notificationDelegate
        }
    }

    func recordHandledPeriod(subscriptionID: UUID, expiry: LocalDate) {
        submissionHistory.recordHandledPeriod(
            subscriptionID: subscriptionID,
            expiry: expiry
        )
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
        let allPlans = SubscriptionNotificationPlan.plans(
            subscriptions: subscriptions,
            referenceDate: referenceDate,
            namespace: namespace
        )
        submissionHistory.retainActivePlans(allPlans)
        let activeIdentifiers = SubscriptionNotificationPlan.activeIdentifiers(
            subscriptions: subscriptions,
            referenceDate: referenceDate,
            namespace: namespace
        )
        do {
            let pendingBeforeCleanup = await center.pendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            let inactivePendingIdentifiers = SubscriptionNotificationPlan.staleManagedIdentifiers(
                in: pendingBeforeCleanup.map(\.identifier),
                activeIdentifiers: activeIdentifiers,
                namespace: namespace,
                obsoleteNamespaces: obsoleteNamespaces
            )
            let pendingAfterInactiveCleanup = await pendingRequests(
                afterRemoving: inactivePendingIdentifiers,
                from: pendingBeforeCleanup
            )
            let plansByIdentifier = Dictionary(
                uniqueKeysWithValues: allPlans.map { ($0.identifier, $0) }
            )
            let outdatedPendingIdentifiers: [String] = pendingAfterInactiveCleanup.compactMap {
                request -> String? in
                guard let plan = plansByIdentifier[request.identifier] else { return nil }
                let storedFingerprint = request.content.userInfo[
                    SubscriptionNotificationPlan.requestFingerprintUserInfoKey
                ] as? String
                guard storedFingerprint != plan.requestFingerprint else { return nil }
                return request.identifier
            }
            let currentPending = await pendingRequests(
                afterRemoving: outdatedPendingIdentifiers,
                from: pendingAfterInactiveCleanup
            )
            // A delivered request has already notified the user. Only pending requests
            // are replaced when their visible content or delivery time changes.
            let currentDelivered = delivered

            let observedIdentifiers = Set(currentPending.map(\.identifier)).union(
                currentDelivered.map(\.request.identifier)
            )
            for plan in allPlans where !plan.isCatchUp
                && observedIdentifiers.contains(plan.identifier) {
                submissionHistory.recordSubmission(of: plan)
            }
            let currentPendingIdentifiers = Set(currentPending.map(\.identifier))
            let managedCurrentPendingIdentifiers = currentPendingIdentifiers.intersection(
                plansByIdentifier.keys
            )
            let selection = SubscriptionNotificationPlan.reconciliationSelection(
                from: allPlans,
                currentPendingIdentifiers: managedCurrentPendingIdentifiers,
                observedIdentifiers: observedIdentifiers,
                reservedPendingCount: currentPending.count
                    - managedCurrentPendingIdentifiers.count,
                wasSubmitted: submissionHistory.contains
            )
            let plans = selection.plansToSubmit
            let deferredCount = selection.deferredCount
            let scheduledIdentifiers = Set(plans.map(\.identifier))
            let stalePendingIdentifiers = SubscriptionNotificationPlan.staleManagedIdentifiers(
                in: currentPending.map(\.identifier),
                activeIdentifiers: selection.pendingIdentifiersToKeep,
                namespace: namespace,
                obsoleteNamespaces: []
            )
            _ = await pendingRequests(
                afterRemoving: stalePendingIdentifiers,
                from: currentPending
            )

            let staleDeliveredIdentifiers = SubscriptionNotificationPlan.staleManagedIdentifiers(
                in: currentDelivered.map(\.request.identifier),
                activeIdentifiers: activeIdentifiers,
                namespace: namespace,
                obsoleteNamespaces: obsoleteNamespaces
            )
            center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIdentifiers)

            let settings = await center.notificationSettings()
            let isAuthorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                status = .authorizationRequired
                return
            }
            guard isAuthorized else {
                status = .denied
                return
            }

            guard !activeIdentifiers.isEmpty else {
                status = .noReminders
                return
            }

            for plan in plans {
                let content = UNMutableNotificationContent()
                switch plan.kind {
                case .expiryReminder:
                    let displayedRemainingDays = plan.isCatchUp
                        ? plan.remainingDays
                        : plan.advanceDays
                    if displayedRemainingDays == 0 {
                        content.title = AppLocalization.string("订阅今天到期")
                        content.body = String(
                            format: AppLocalization.string("%@ 今天到期（%@），请及时处理。"),
                            plan.subscriptionName,
                            plan.expiry.displayText
                        )
                    } else {
                        content.title = AppLocalization.string("订阅即将到期")
                        content.body = String(
                            format: AppLocalization.string("%@ 将在 %d 天后到期（%@）。"),
                            plan.subscriptionName,
                            displayedRemainingDays,
                            plan.expiry.displayText
                        )
                    }
                case .renewalConfirmation:
                    content.title = AppLocalization.string("确认订阅续费")
                    content.body = String(
                        format: AppLocalization.string("%@ 今天到期（%@），请确认服务商是否已自动续费。"),
                        plan.subscriptionName,
                        plan.expiry.displayText
                    )
                }
                content.sound = .default
                content.userInfo = [
                    "subscriptionID": plan.subscriptionID.uuidString,
                    SubscriptionNotificationPlan.requestFingerprintUserInfoKey:
                        plan.requestFingerprint,
                ]
                let trigger: UNNotificationTrigger? = if plan.isCatchUp {
                    nil
                } else {
                    UNCalendarNotificationTrigger(
                        dateMatching: plan.deliveryComponents,
                        repeats: false
                    )
                }
                do {
                    try await center.add(
                        UNNotificationRequest(
                            identifier: plan.identifier,
                            content: content,
                            trigger: trigger
                        )
                    )
                    if plan.isCatchUp {
                        submissionHistory.recordSubmission(of: plan)
                    }
                } catch {
                    let notificationError = error as NSError
                    AppLog.lifecycle.error(
                        "Failed to schedule a subscription notification: domain=\(notificationError.domain, privacy: .public) code=\(notificationError.code)"
                    )
                }
            }
            let reconciledPending = await settledPendingRequests(
                expectedIdentifiers: selection.expectedFutureIdentifiers
            )
            let reconciledDelivered = await center.deliveredNotifications()
            let reconciledIdentifiers = Set(reconciledPending.map(\.identifier)).union(
                reconciledDelivered.map(\.request.identifier)
            )
            for plan in allPlans where !plan.isCatchUp
                && reconciledIdentifiers.contains(plan.identifier) {
                submissionHistory.recordSubmission(of: plan)
            }
            let submittedCatchUpPlans = SubscriptionNotificationPlan
                .latestCatchUpPlans(in: allPlans)
                .filter(submissionHistory.contains)
            let pendingFutureIdentifiers = Set(
                allPlans.filter { !$0.isCatchUp }.map(\.identifier)
            ).intersection(reconciledIdentifiers)
            let successfulAttemptIdentifiers = reconciledIdentifiers.union(
                submittedCatchUpPlans.map(\.identifier)
            )
            let scheduledCount = pendingFutureIdentifiers.count + submittedCatchUpPlans.count
            status = .ready(
                scheduledCount: scheduledCount,
                deferredCount: deferredCount,
                failedCount: scheduledIdentifiers.subtracting(
                    successfulAttemptIdentifiers
                ).count
            )
        } catch {
            status = .failed
            AppLog.lifecycle.error("Failed to reconcile subscription notifications")
        }
    }

    private func pendingRequests(
        afterRemoving identifiers: [String],
        from currentRequests: [UNNotificationRequest]
    ) async -> [UNNotificationRequest] {
        guard !identifiers.isEmpty else { return currentRequests }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        let removedIdentifiers = Set(identifiers)
        var requests = currentRequests
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(50))
            requests = await center.pendingNotificationRequests()
            if removedIdentifiers.isDisjoint(with: requests.map(\.identifier)) {
                break
            }
        }
        return requests
    }

    private func settledPendingRequests(
        expectedIdentifiers: Set<String>
    ) async -> [UNNotificationRequest] {
        var requests = await center.pendingNotificationRequests()
        for _ in 0..<3 {
            let observedIdentifiers = Set(requests.map(\.identifier))
            guard !expectedIdentifiers.isSubset(of: observedIdentifiers) else { break }
            try? await Task.sleep(for: .milliseconds(100))
            requests = await center.pendingNotificationRequests()
        }
        return requests
    }

    func requestAuthorization() async {
        guard isSystemIntegrationEnabled else {
            status = .idle
            return
        }
        do {
            let isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
            status = isAuthorized ? .idle : .denied
        } catch {
            status = .failed
            AppLog.lifecycle.error("Failed to request notification authorization")
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
    private let submissionHistory: SubscriptionNotificationSubmissionHistory

    init(
        selection: SubscriptionNotificationSelection,
        submissionHistory: SubscriptionNotificationSubmissionHistory
    ) {
        self.selection = selection
        self.submissionHistory = submissionHistory
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let value = response.notification.request.content.userInfo["subscriptionID"] as? String,
              let id = UUID(uuidString: value) else {
            return
        }
        await submissionHistory.recordAcknowledgement(
            of: response.notification.request.identifier
        )
        await selection.select(id)
    }
}
