import SwiftUI

@main
struct PeriodicApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup(AppConfiguration.displayName, id: AppConfiguration.mainWindowID) {
            ContentView()
                .environment(services)
                .environment(\.appleIconCache, services.appleIconCache)
                .modifier(AppearanceModifier())
                .modifier(LocalizationModifier())
                .modifier(CurrencyDisplayModifier())
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands()
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .environment(services)
                .environment(\.appleIconCache, services.appleIconCache)
                .modifier(AppearanceModifier())
                .modifier(LocalizationModifier())
                .modifier(CurrencyDisplayModifier())
        }
        .windowResizability(.contentSize)
    }
}
