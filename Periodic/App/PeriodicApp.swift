import SwiftUI

@main
struct PeriodicApp: App {
    @State private var services: AppServices
    @State private var updates: AppUpdateService
    @State private var menuBarFeature = MenuBarFeature()
    @State private var windowRouter = AppWindowRouter()
    @AppStorage(PreferenceKey.menuBarEnabled) private var menuBarEnabled = true

    init() {
        let services = AppServices()
        _services = State(initialValue: services)
        _updates = State(initialValue: AppUpdateService(
            terminationGuard: services.terminationGuard
        ))
    }

    var body: some Scene {
        WindowGroup(AppConfiguration.displayName, id: AppConfiguration.mainWindowID) {
            ContentView()
                .environment(services)
                .environment(windowRouter)
                .environment(\.appleIconCache, services.appleIconCache)
                .modifier(AppearanceModifier())
                .modifier(LocalizationModifier())
                .modifier(CurrencyDisplayModifier())
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(updates: updates)
            SidebarCommands()
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarSubscriptionView(
                feature: menuBarFeature,
                services: services,
                windowRouter: windowRouter
            )
            .environment(\.appleIconCache, services.appleIconCache)
            .modifier(AppearanceModifier())
            .modifier(LocalizationModifier())
            .modifier(CurrencyDisplayModifier())
        } label: {
            MenuBarStatusLabel(feature: menuBarFeature, services: services)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(services)
                .environment(updates)
                .environment(\.appleIconCache, services.appleIconCache)
                .modifier(AppearanceModifier())
                .modifier(LocalizationModifier())
                .modifier(CurrencyDisplayModifier())
        }
        .windowResizability(.contentSize)
    }
}
