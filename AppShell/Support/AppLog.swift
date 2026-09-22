import OSLog

enum AppLog {
    static let lifecycle = Logger(
        subsystem: AppConfiguration.subsystem,
        category: "Lifecycle"
    )
}
