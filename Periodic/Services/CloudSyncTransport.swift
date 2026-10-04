import Foundation

protocol CloudSyncTransport: Sendable {
    func status() async -> CloudSyncTransportStatus
    func checkAvailability() async throws
    func previewRemoteInventory() async throws -> CloudRecordInventory
    func start(automaticallySync: Bool) async throws
    func stop() async
    func setRemoteChangeHandler(
        _ handler: (@Sendable () -> Void)?
    ) async
    func notifyLocalChanges() async throws
    func syncNow() async throws
}

extension CloudKitSyncEngineAdapter: CloudSyncTransport {}
