import Foundation

/// Keeps application replacement from interrupting operations that outlive their sheets.
@MainActor
final class ApplicationTerminationGuard {
    struct Operation: Hashable {
        fileprivate let id = UUID()
    }

    var hasPendingOperations: Bool { !operations.isEmpty }

    private var operations: Set<Operation> = []
    private var idleActions: [() -> Void] = []

    func beginOperation() -> Operation {
        let operation = Operation()
        operations.insert(operation)
        return operation
    }

    func endOperation(_ operation: Operation) {
        guard operations.remove(operation) != nil, operations.isEmpty else { return }
        let actions = idleActions
        idleActions.removeAll()
        for action in actions {
            whenIdle(action)
        }
    }

    func whenIdle(_ action: @escaping () -> Void) {
        if hasPendingOperations {
            idleActions.append(action)
        } else {
            action()
        }
    }
}
