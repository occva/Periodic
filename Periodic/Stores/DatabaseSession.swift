import Foundation
import SwiftData
import Synchronization

struct DatabaseSession: Sendable {
    let modelContainer: ModelContainer
    let modelExecutor: DefaultSerialModelExecutor
    let serialExecutor: DispatchSerialQueue

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let queue = DispatchSerialQueue(label: "Periodic.Database")
        serialExecutor = queue
        let executor = Mutex<DefaultSerialModelExecutor?>(nil)
        let completion = DispatchSemaphore(value: 0)
        queue.async {
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false
            executor.withLock { $0 = DefaultSerialModelExecutor(modelContext: context) }
            completion.signal()
        }
        completion.wait()
        modelExecutor = executor.withLock {
            guard let result = $0 else {
                preconditionFailure("Database executor initialization did not complete")
            }
            return result
        }
    }
}
