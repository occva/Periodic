import SwiftUI

struct AppCommands: Commands {
    let updates: AppUpdateService
    @AppStorage(PreferenceKey.language) private var language = AppLanguage.system
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.createSubscriptionAction) private var createSubscription

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(action: updates.checkForUpdates) {
                Text("检查更新…", tableName: "Updates")
            }
            .disabled(!updates.canCheckForUpdates)
            .environment(\.locale, language.locale)
            if updates.isWaitingToRestart {
                Button(action: updates.resumePendingInstallation) {
                    Text("完成编辑并重启更新", tableName: "Updates")
                }
                .environment(\.locale, language.locale)
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("新建订阅") {
                createSubscription?()
            }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(createSubscription == nil)

            Button("新建窗口") {
                openWindow(id: AppConfiguration.mainWindowID)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}
