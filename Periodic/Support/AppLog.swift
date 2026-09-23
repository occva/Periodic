import OSLog

enum AppLog {
    static let lifecycle = Logger(
        subsystem: AppConfiguration.subsystem,
        category: "Lifecycle"
    )

    static let persistence = Logger(
        subsystem: AppConfiguration.subsystem,
        category: "Persistence"
    )
}
