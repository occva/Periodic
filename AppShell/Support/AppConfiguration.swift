import Foundation

enum AppConfiguration {
    static let displayName = "AppShell"
    static let mainWindowID = "main"
    static let subsystem = Bundle.main.bundleIdentifier ?? "local.lhg.AppShell"

    static var storeURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "AppShell", directoryHint: .isDirectory)
            .appending(path: "default.store")
    }
}
