enum ApplicationRestartReadiness {
    static func canRestart(
        hasAttachedSheets: Bool,
        hasModalWindow: Bool,
        hasPendingOperations: Bool = false
    ) -> Bool {
        !hasAttachedSheets && !hasModalWindow && !hasPendingOperations
    }
}
