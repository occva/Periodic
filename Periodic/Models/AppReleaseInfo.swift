import Foundation

struct AppReleaseInfo: Equatable, Sendable {
    let version: String
    let build: String

    static var current: AppReleaseInfo {
        AppReleaseInfo(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "?",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "?"
        )
    }
}
