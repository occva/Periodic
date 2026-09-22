import Foundation

enum AppConfiguration {
    static let displayName = "Periodic"
    static let mainWindowID = "main"
    static let subsystem = Bundle.main.bundleIdentifier ?? "local.lhg.Periodic"

    static var storeURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Periodic", directoryHint: .isDirectory)
            .appending(path: "default.store")
    }
}
