import AppKit
import Combine
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdateService: NSObject, SPUUpdaterDelegate {
    let availability: AppUpdateConfiguration.Availability
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    private(set) var isWaitingToRestart = false
    private(set) var startupError: PresentedError?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: Set<AnyCancellable> = []
    @ObservationIgnored private var pendingInstallation: (() -> Void)?
    @ObservationIgnored private let terminationGuard: ApplicationTerminationGuard

    init(
        configuration: AppUpdateConfiguration = .current,
        terminationGuard: ApplicationTerminationGuard = ApplicationTerminationGuard()
    ) {
        availability = configuration.availability
        self.terminationGuard = terminationGuard
        super.init()
        guard availability == .available else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        do {
            try controller.updater.start()
            observeUpdater(controller.updater)
        } catch {
            startupError = PresentedError(error, title: "无法启动应用更新")
            AppLog.updates.error("Updater failed to start: \(error.localizedDescription, privacy: .private)")
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }

    func resumePendingInstallation() {
        guard let pendingInstallation else { return }
        if terminationGuard.hasPendingOperations {
            terminationGuard.whenIdle { [weak self] in
                // Completing an operation may present its receipt or destination panel.
                DispatchQueue.main.async { [weak self] in
                    self?.resumePendingInstallation()
                }
            }
            return
        }
        guard canRestart else { return }
        self.pendingInstallation = nil
        isWaitingToRestart = false
        pendingInstallation()
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard !canRestart else { return false }
        pendingInstallation = installHandler
        isWaitingToRestart = true
        // Sheets may contain drafts; data operations may continue after their sheets close.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("更新已准备好", table: "Updates")
        alert.informativeText = AppLocalization.string(
            "请先保存或取消所有打开的编辑和对话框，并等待数据操作完成。之后 Periodic 将自动安装更新并重新启动。",
            table: "Updates"
        )
        alert.addButton(withTitle: AppLocalization.string("好", table: "Updates"))
        alert.runModal()
        DispatchQueue.main.async { [weak self] in
            self?.resumePendingInstallation()
        }
        return true
    }

    private var canRestart: Bool {
        ApplicationRestartReadiness.canRestart(
            hasAttachedSheets: NSApp.windows.contains { $0.attachedSheet != nil },
            hasModalWindow: NSApp.modalWindow != nil,
            hasPendingOperations: terminationGuard.hasPendingOperations
        )
    }

    private func observeUpdater(_ updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }
            .store(in: &observations)
        updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] in self?.lastUpdateCheckDate = $0 }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)
            .merge(with: NotificationCenter.default.publisher(
                for: NSWindow.willCloseNotification
            ))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resumePendingInstallation() }
            .store(in: &observations)
    }
}
