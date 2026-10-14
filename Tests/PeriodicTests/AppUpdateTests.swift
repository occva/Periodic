import Foundation
import Testing
@testable import Periodic

struct AppUpdateTests {
    private let feedURL = "https://github.com/occva/Periodic/releases/latest/download/appcast.xml"
    private let publicKey = Data(repeating: 1, count: 32).base64EncodedString()

    @Test func validProductionConfigurationEnablesUpdates() {
        #expect(configuration().availability == .available)
    }

    @Test func developmentAndIsolatedRunsDisableUpdatesEvenWithValidConfiguration() {
        #expect(configuration(isDevelopmentBuild: true).availability == .developmentBuild)
        #expect(configuration(isIsolatedRun: true).availability == .developmentBuild)
    }

    @Test func rejectsMissingOrInsecureFeed() {
        for url in [nil, "", "http://example.com/appcast.xml", "file:///tmp/appcast.xml",
                    "https:///appcast.xml", "https://user:password@example.com/appcast.xml"] {
            #expect(AppUpdateConfiguration(
                feedURL: url,
                publicKey: publicKey,
                isDevelopmentBuild: false,
                isIsolatedRun: false
            ).availability == .invalidConfiguration)
        }
    }

    @Test func rejectsMissingOrInvalidSigningKey() {
        for key in [nil, "", "$(SPARKLE_PUBLIC_ED_KEY)", "not-base64",
                    Data(repeating: 1, count: 31).base64EncodedString(),
                    Data(repeating: 1, count: 33).base64EncodedString()] {
            #expect(AppUpdateConfiguration(
                feedURL: feedURL,
                publicKey: key,
                isDevelopmentBuild: false,
                isIsolatedRun: false
            ).availability == .invalidConfiguration)
        }
    }

    @Test func restartWaitsForEverySheetAndModalDialog() {
        #expect(ApplicationRestartReadiness.canRestart(
            hasAttachedSheets: false, hasModalWindow: false
        ))
        for (sheets, modal) in [(true, false), (false, true), (true, true)] {
            #expect(!ApplicationRestartReadiness.canRestart(
                hasAttachedSheets: sheets, hasModalWindow: modal
            ))
        }
        #expect(!ApplicationRestartReadiness.canRestart(
            hasAttachedSheets: false,
            hasModalWindow: false,
            hasPendingOperations: true
        ))
    }

    @Test @MainActor func disabledUpdaterDoesNotStartOrChangePreferences() {
        let updates = AppUpdateService(configuration: configuration(isIsolatedRun: true))
        updates.checkForUpdates()
        updates.setAutomaticallyChecksForUpdates(true)
        updates.setAutomaticallyDownloadsUpdates(true)

        #expect(!updates.canCheckForUpdates)
        #expect(!updates.automaticallyChecksForUpdates)
        #expect(!updates.automaticallyDownloadsUpdates)
        #expect(updates.lastUpdateCheckDate == nil)
        #expect(updates.startupError == nil)
        #expect(!updates.isWaitingToRestart)
    }

    private func configuration(
        isDevelopmentBuild: Bool = false,
        isIsolatedRun: Bool = false
    ) -> AppUpdateConfiguration {
        AppUpdateConfiguration(
            feedURL: feedURL,
            publicKey: publicKey,
            isDevelopmentBuild: isDevelopmentBuild,
            isIsolatedRun: isIsolatedRun
        )
    }
}
