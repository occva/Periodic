import Foundation

enum AppConfiguration {
    static let displayName = "Periodic"
    static let mainWindowID = "main"
    static let subsystem = Bundle.main.bundleIdentifier ?? "local.lhg.Periodic"
    static var iCloudContainerIdentifier: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "PeriodicICloudContainerIdentifier"
        ) as? String,
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
    static let defaultCloudZoneName = "Periodic"

    static var applicationSupportRoot: URL {
        URL.applicationSupportDirectory
            .appending(path: "Periodic", directoryHint: .isDirectory)
    }

    static var datasetDescriptorURL: URL {
        applicationSupportRoot.appending(path: "active-dataset.json")
    }

    static var deviceIdentityURL: URL {
        applicationSupportRoot.appending(path: "device-identity.json")
    }

    static var cloudAssetStagingRoot: URL {
        applicationSupportRoot.appending(
            path: "CloudAssetStaging",
            directoryHint: .isDirectory
        )
    }

    static var cloudSafetySnapshotRoot: URL {
        applicationSupportRoot.appending(
            path: "iCloud Safety Snapshots",
            directoryHint: .isDirectory
        )
    }

    static func cloudSyncStateURL(datasetID: UUID) -> URL {
        applicationSupportRoot
            .appending(path: "CloudSync", directoryHint: .isDirectory)
            .appending(path: datasetID.uuidString, directoryHint: .isDirectory)
            .appending(path: "sync-engine-state.plist")
    }

    static func cloudAccountIdentityURL(datasetID: UUID) -> URL {
        applicationSupportRoot
            .appending(path: "CloudSync", directoryHint: .isDirectory)
            .appending(path: datasetID.uuidString, directoryHint: .isDirectory)
            .appending(path: "account-identity")
    }

    static var storeURL: URL {
        applicationSupportRoot.appending(path: "default.store")
    }
}
