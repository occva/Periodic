import Foundation
import Testing
@testable import Periodic

struct CloudSyncCoordinatorTests {
    @Test func remoteInventoryMapsToPresentationSummary() {
        let summary = CloudSyncDataSummary(
            remoteInventory: CloudRecordInventory(
                recordCounts: [
                    .subscription: 3,
                    .subscriptionPeriod: 4,
                    .subscriptionPayment: 5,
                    .serviceTemplate: 6,
                    .templateCategory: 7,
                    .builtinTemplateCategoryAssignment: 8,
                    .iconAsset: 9,
                ],
                estimatedAssetBytes: 10
            )
        )

        #expect(summary.subscriptions == 3)
        #expect(summary.periods == 4)
        #expect(summary.payments == 5)
        #expect(summary.templates == 6)
        #expect(summary.categories == 7)
        #expect(summary.assignments == 8)
        #expect(summary.imageCount == 9)
        #expect(summary.estimatedBytes == 10)
        #expect(!summary.isEmpty)
    }

    @MainActor
    @Test func recordsSuccessOnlyWhenTransportFinishesIdle() async throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set(true, forKey: PreferenceKey.iCloudSyncEnabled)
        let transport = FakeCloudSyncTransport(statusAfterSync: .idle)
        let coordinator = makeCoordinator(
            transport: transport,
            defaults: defaults
        )

        await coordinator.syncNow()

        #expect(coordinator.snapshot.phase == .idle)
        #expect(coordinator.snapshot.lastSuccessfulSyncAt != nil)
        #expect(
            defaults.object(
                forKey: PreferenceKey.iCloudLastSuccessfulSyncAt
            ) as? Date != nil
        )
    }

    @MainActor
    @Test func doesNotRecordSuccessWhileTransportIsRetrying() async throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set(true, forKey: PreferenceKey.iCloudSyncEnabled)
        let transport = FakeCloudSyncTransport(statusAfterSync: .retrying)
        let coordinator = makeCoordinator(
            transport: transport,
            defaults: defaults
        )

        await coordinator.syncNow()

        #expect(coordinator.snapshot.phase == .retrying)
        #expect(coordinator.snapshot.lastSuccessfulSyncAt == nil)
        #expect(
            defaults.object(
                forKey: PreferenceKey.iCloudLastSuccessfulSyncAt
            ) == nil
        )
    }

    @MainActor
    private func makeCoordinator(
        transport: FakeCloudSyncTransport,
        defaults: UserDefaults
    ) -> CloudSyncCoordinator {
        CloudSyncCoordinator(
            transport: transport,
            bootstrapStore: nil,
            statusStore: nil,
            dataExchange: nil,
            metadataStore: nil,
            descriptorRepository: nil,
            safetySnapshotService: CloudSyncSafetySnapshotService(
                root: FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString)
            ),
            descriptor: .local(),
            defaults: defaults
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try #require(
            UserDefaults(suiteName: defaultsSuiteName)
        )
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    private var defaultsSuiteName: String {
        "CloudSyncCoordinatorTests"
    }
}

private actor FakeCloudSyncTransport: CloudSyncTransport {
    private let statusAfterSync: CloudSyncTransportStatus
    private var currentStatus: CloudSyncTransportStatus = .idle

    init(statusAfterSync: CloudSyncTransportStatus) {
        self.statusAfterSync = statusAfterSync
    }

    func status() -> CloudSyncTransportStatus {
        currentStatus
    }

    func checkAvailability() throws {}

    func previewRemoteInventory() -> CloudRecordInventory {
        .empty
    }

    func start(automaticallySync: Bool) throws {
        currentStatus = .idle
    }

    func stop() {
        currentStatus = .stopped
    }

    func setRemoteChangeHandler(
        _ handler: (@Sendable () -> Void)?
    ) {}

    func notifyLocalChanges() throws {}

    func syncNow() throws {
        currentStatus = statusAfterSync
    }
}
