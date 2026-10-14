import Foundation

struct AppUpdateConfiguration: Equatable, Sendable {
    enum Availability: Equatable, Sendable {
        case available
        case developmentBuild
        case invalidConfiguration
    }

    let availability: Availability

    init(
        feedURL: String?,
        publicKey: String?,
        isDevelopmentBuild: Bool,
        isIsolatedRun: Bool
    ) {
        if isDevelopmentBuild || isIsolatedRun {
            availability = .developmentBuild
            return
        }
        guard let feedURL,
              let components = URLComponents(string: feedURL),
              components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let publicKey,
              let keyData = Data(base64Encoded: publicKey),
              keyData.count == 32 else {
            availability = .invalidConfiguration
            return
        }
        availability = .available
    }

    static var current: AppUpdateConfiguration {
        #if DEBUG
        let isDevelopmentBuild = true
        #else
        let isDevelopmentBuild = false
        #endif
        let process = ProcessInfo.processInfo
        return AppUpdateConfiguration(
            feedURL: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            isDevelopmentBuild: isDevelopmentBuild,
            isIsolatedRun: process.environment["XCTestConfigurationFilePath"] != nil
                || process.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
                || process.arguments.contains("-store-in-memory")
        )
    }
}
