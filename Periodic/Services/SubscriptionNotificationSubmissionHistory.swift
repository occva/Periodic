import Foundation

@MainActor
final class SubscriptionNotificationSubmissionHistory {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = PreferenceKey.submittedNotificationRequests
    ) {
        self.defaults = defaults
        self.key = key
    }

    func contains(_ plan: SubscriptionNotificationPlan) -> Bool {
        let values = storedValues
        return values.contains(submissionKey(for: plan))
            || values.contains(legacySubmissionKey(for: plan))
            || values.contains(acknowledgementKey(for: plan.identifier))
            || values.contains(
                handledPeriodKey(
                    subscriptionID: plan.subscriptionID,
                    expiry: plan.expiry
                )
            )
    }

    func recordSubmission(of plan: SubscriptionNotificationPlan) {
        update { $0.insert(submissionKey(for: plan)) }
    }

    func recordAcknowledgement(of identifier: String) {
        update { $0.insert(acknowledgementKey(for: identifier)) }
    }

    func recordHandledPeriod(subscriptionID: UUID, expiry: LocalDate) {
        update {
            $0.insert(
                handledPeriodKey(subscriptionID: subscriptionID, expiry: expiry)
            )
        }
    }

    func retainActivePlans(_ plans: [SubscriptionNotificationPlan]) {
        let activeValues = Set(plans.flatMap { plan in
            [
                submissionKey(for: plan),
                legacySubmissionKey(for: plan),
                acknowledgementKey(for: plan.identifier),
                handledPeriodKey(
                    subscriptionID: plan.subscriptionID,
                    expiry: plan.expiry
                ),
            ]
        })
        let retainedValues = storedValues.intersection(activeValues)
        guard retainedValues != storedValues else { return }
        defaults.set(retainedValues.sorted(), forKey: key)
    }

    private var storedValues: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private func update(_ change: (inout Set<String>) -> Void) {
        var values = storedValues
        change(&values)
        defaults.set(values.sorted(), forKey: key)
    }

    private func submissionKey(for plan: SubscriptionNotificationPlan) -> String {
        "submission|" + plan.submissionFingerprint
    }

    private func legacySubmissionKey(for plan: SubscriptionNotificationPlan) -> String {
        "submission|" + plan.legacySubmissionFingerprint
    }

    private func acknowledgementKey(for identifier: String) -> String {
        "acknowledgement|" + identifier
    }

    private func handledPeriodKey(subscriptionID: UUID, expiry: LocalDate) -> String {
        ["handled-period", subscriptionID.uuidString, String(expiry.dayNumber)]
            .joined(separator: "|")
    }
}
