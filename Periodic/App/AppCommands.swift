import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.createSubscriptionAction) private var createSubscription

    var body: some Commands {
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
