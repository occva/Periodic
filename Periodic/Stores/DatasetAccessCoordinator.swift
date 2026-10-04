import Foundation

actor DatasetAccessCoordinator {
    struct WriteLease: Hashable, Sendable {
        fileprivate let id: UUID
    }

    struct MaintenanceLease: Hashable, Sendable {
        fileprivate let id: UUID
    }

    struct Snapshot: Equatable, Sendable {
        let activeWriteCount: Int
        let pendingWriteCount: Int
        let isMaintenanceActive: Bool
    }

    nonisolated let descriptor: DatasetDescriptor?
    nonisolated let deviceID: UUID

    private var activeWriteIDs: Set<UUID> = []
    private var writeWaiters: [WriteWaiter] = []
    private var maintenanceID: UUID?
    private var writeReleaseHandler: (@Sendable () -> Void)?

    init(
        descriptor: DatasetDescriptor? = nil,
        deviceID: UUID = UUID()
    ) {
        self.descriptor = descriptor
        self.deviceID = deviceID
    }

    func acquireWrite() async throws -> WriteLease {
        try Task.checkCancellation()
        guard maintenanceID == nil else {
            throw DatasetAccessError.maintenanceInProgress
        }
        guard activeWriteIDs.isEmpty else {
            let lease = await withCheckedContinuation { continuation in
                writeWaiters.append(
                    WriteWaiter(continuation: continuation)
                )
            }
            if Task.isCancelled {
                releaseWrite(lease)
                throw CancellationError()
            }
            return lease
        }
        let lease = WriteLease(id: UUID())
        activeWriteIDs.insert(lease.id)
        return lease
    }

    func releaseWrite(_ lease: WriteLease) {
        guard activeWriteIDs.remove(lease.id) != nil else { return }
        if maintenanceID == nil, !writeWaiters.isEmpty {
            let waiter = writeWaiters.removeFirst()
            let nextLease = WriteLease(id: UUID())
            activeWriteIDs.insert(nextLease.id)
            waiter.continuation.resume(returning: nextLease)
        }
        writeReleaseHandler?()
    }

    func setWriteReleaseHandler(
        _ handler: (@Sendable () -> Void)?
    ) {
        writeReleaseHandler = handler
    }

    func beginMaintenance() throws -> MaintenanceLease {
        guard maintenanceID == nil else {
            throw DatasetAccessError.maintenanceInProgress
        }
        guard activeWriteIDs.isEmpty, writeWaiters.isEmpty else {
            throw DatasetAccessError.writeInProgress
        }
        let lease = MaintenanceLease(id: UUID())
        maintenanceID = lease.id
        return lease
    }

    func endMaintenance(_ lease: MaintenanceLease) {
        guard maintenanceID == lease.id else { return }
        maintenanceID = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(
            activeWriteCount: activeWriteIDs.count,
            pendingWriteCount: writeWaiters.count,
            isMaintenanceActive: maintenanceID != nil
        )
    }

    private struct WriteWaiter {
        let continuation: CheckedContinuation<WriteLease, Never>
    }
}

enum DatasetAccessError: LocalizedError, Equatable {
    case maintenanceInProgress
    case writeInProgress

    var errorDescription: String? {
        switch self {
        case .maintenanceInProgress:
            "正在维护订阅数据，请等待操作完成后重试。"
        case .writeInProgress:
            "仍有数据正在保存，暂时无法开始维护。"
        }
    }
}
