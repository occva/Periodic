import Observation

/// Keeps retiring form controls bound to their own draft after the active editor closes.
@MainActor
@Observable
final class SubscriptionSharingPeriodEditorSession {
    var draft: SubscriptionSharingPeriodDraft

    init(draft: SubscriptionSharingPeriodDraft) {
        self.draft = draft
    }
}
