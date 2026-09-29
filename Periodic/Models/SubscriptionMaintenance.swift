import Foundation

enum SubscriptionCreationHistoryPolicy: Equatable, Sendable {
    case recordInitialPeriod
    case skipInitialPeriod
}

struct SubscriptionMutationTarget: Hashable, Sendable {
    let id: UUID
    let expectedRevision: Int64
}

struct SubscriptionDeletionPreview: Identifiable, Equatable, Sendable {
    let id: UUID
    let targets: [SubscriptionMutationTarget]
    let subscriptionCount: Int
    let periodCount: Int

    init(
        id: UUID = UUID(),
        targets: [SubscriptionMutationTarget],
        subscriptionCount: Int,
        periodCount: Int
    ) {
        self.id = id
        self.targets = targets
        self.subscriptionCount = subscriptionCount
        self.periodCount = periodCount
    }
}

struct SubscriptionDeletionResult: Sendable {
    let deletedSubscriptionCount: Int
    let deletedPeriodCount: Int
    let unreferencedIconReferences: Set<String>
}

struct SubscriptionDeletionOutcome: Sendable {
    let pendingIconCleanupCount: Int
}
