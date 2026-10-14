import Foundation
import Testing
@testable import Periodic

@MainActor
struct ApplicationTerminationGuardTests {
    @Test func waitsForAllOperationsAndRunsIdleActionOnce() {
        let guardState = ApplicationTerminationGuard()
        let first = guardState.beginOperation()
        let second = guardState.beginOperation()
        var invocations = 0
        guardState.whenIdle { invocations += 1 }

        guardState.endOperation(first)
        #expect(guardState.hasPendingOperations)
        #expect(invocations == 0)
        guardState.endOperation(second)
        #expect(!guardState.hasPendingOperations)
        #expect(invocations == 1)
        guardState.endOperation(second)
        #expect(invocations == 1)
    }

    @Test func idleActionCanBeginAnotherProtectedOperation() throws {
        let guardState = ApplicationTerminationGuard()
        let first = guardState.beginOperation()
        var next: ApplicationTerminationGuard.Operation?
        guardState.whenIdle { next = guardState.beginOperation() }

        guardState.endOperation(first)
        #expect(guardState.hasPendingOperations)
        guardState.endOperation(try #require(next))
        #expect(!guardState.hasPendingOperations)
    }

    @Test func failingDataInspectionReleasesRestartProtection() async throws {
        let services = AppServices(inMemory: true)
        let feature = DataExchangeFeature()
        let missing = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString + ".periodicdata")
        feature.inspect(
            .success([missing]),
            using: try #require(services.dataExchange),
            terminationGuard: services.terminationGuard
        )
        #expect(services.terminationGuard.hasPendingOperations)

        await withCheckedContinuation { continuation in
            services.terminationGuard.whenIdle { continuation.resume() }
        }
        #expect(!services.terminationGuard.hasPendingOperations)
        #expect(feature.phase == .idle)
        #expect(feature.error != nil)
    }

    @Test func exportPreparationProtectsRestartUntilPreviewIsReady() async throws {
        let services = AppServices(inMemory: true)
        let feature = DataExchangeFeature()
        feature.requestExport(
            using: try #require(services.dataExchange),
            terminationGuard: services.terminationGuard
        )
        #expect(services.terminationGuard.hasPendingOperations)

        await withCheckedContinuation { continuation in
            services.terminationGuard.whenIdle { continuation.resume() }
        }
        #expect(!services.terminationGuard.hasPendingOperations)
        #expect(feature.phase == .awaitingExportConfirmation)
        #expect(feature.isPresentingExportPreview)
        #expect(feature.error == nil)
    }
}
