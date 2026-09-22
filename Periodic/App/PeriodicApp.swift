import SwiftUI

@main
struct PeriodicApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup(AppConfiguration.displayName, id: AppConfiguration.mainWindowID) {
            ContentView()
                .environment(services)
                .modifier(AppearanceModifier())
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands()
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .environment(services)
                .modifier(AppearanceModifier())
        }
        .windowResizability(.contentSize)
    }
}
