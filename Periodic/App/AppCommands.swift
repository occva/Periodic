import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建窗口") {
                openWindow(id: AppConfiguration.mainWindowID)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}
