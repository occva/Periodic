import Foundation

enum CloudSyncPhase: Equatable, Sendable {
    case disabled
    case checking
    case preparing
    case idle
    case syncing
    case retrying
    case needsAccount
    case accountChanged
    case conflicted
    case failed
}

struct CloudSyncDataSummary: Equatable, Sendable {
    let subscriptions: Int
    let periods: Int
    let payments: Int
    let templates: Int
    let categories: Int
    let assignments: Int
    let imageCount: Int
    let estimatedBytes: Int64

    var recordCount: Int {
        subscriptions
            + periods
            + payments
            + templates
            + categories
            + assignments
    }

    var isEmpty: Bool {
        recordCount == 0 && imageCount == 0
    }

    init(
        subscriptions: Int,
        periods: Int,
        payments: Int,
        templates: Int,
        categories: Int,
        assignments: Int,
        imageCount: Int,
        estimatedBytes: Int64
    ) {
        self.subscriptions = subscriptions
        self.periods = periods
        self.payments = payments
        self.templates = templates
        self.categories = categories
        self.assignments = assignments
        self.imageCount = imageCount
        self.estimatedBytes = estimatedBytes
    }

    init(remoteInventory: CloudRecordInventory) {
        self.init(
            subscriptions: remoteInventory.count(for: .subscription),
            periods: remoteInventory.count(for: .subscriptionPeriod),
            payments: remoteInventory.count(for: .subscriptionPayment),
            templates: remoteInventory.count(for: .serviceTemplate),
            categories: remoteInventory.count(for: .templateCategory),
            assignments: remoteInventory.count(
                for: .builtinTemplateCategoryAssignment
            ),
            imageCount: remoteInventory.count(for: .iconAsset),
            estimatedBytes: remoteInventory.estimatedAssetBytes
        )
    }
}

struct CloudEnablementPreview: Equatable, Sendable {
    let localSummary: CloudSyncDataSummary
    let remoteSummary: CloudSyncDataSummary
    let mergeDescription: String
}

struct CloudSyncQueueSnapshot: Equatable, Sendable {
    let pendingUploadCount: Int
    let pendingDownloadCount: Int
    let conflictCount: Int

    static let empty = CloudSyncQueueSnapshot(
        pendingUploadCount: 0,
        pendingDownloadCount: 0,
        conflictCount: 0
    )
}

struct CloudSyncConflictSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let recordType: SyncRecordType
    let recordID: String
    let fieldNames: [String]
    let localValues: [String: SyncValue]
    let remoteValues: [String: SyncValue]
    let involvesDeletion: Bool
    let createdAt: Date

    var canResolveDirectly: Bool {
        !involvesDeletion
    }
}

struct CloudSyncPresentationSnapshot: Equatable, Sendable {
    let isEnabled: Bool
    let phase: CloudSyncPhase
    let localSummary: CloudSyncDataSummary?
    let queue: CloudSyncQueueSnapshot
    let conflicts: [CloudSyncConflictSummary]
    let lastSuccessfulSyncAt: Date?
    let lastSafetySnapshotURL: URL?
    let errorMessage: String?

    static let disabled = CloudSyncPresentationSnapshot(
        isEnabled: false,
        phase: .disabled,
        localSummary: nil,
        queue: .empty,
        conflicts: [],
        lastSuccessfulSyncAt: nil,
        lastSafetySnapshotURL: nil,
        errorMessage: nil
    )
}
