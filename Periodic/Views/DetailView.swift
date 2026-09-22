import SwiftUI

struct DetailView: View {
    @Environment(AppServices.self) private var services

    let destination: AppDestination
    let session: WindowSession

    var body: some View {
        Group {
            switch destination {
            case .overview:
                OverviewView(session: session)
            case .timeline:
                TimelineView(session: session)
            case .dashboard:
                DashboardView(session: session)
            case .templates:
                TemplateLibraryView(presentation: .embedded) { input in
                    guard let store = services.subscriptionStore else {
                        throw DetailViewError.storeUnavailable
                    }
                    _ = try await store.create(input)
                    services.notifySubscriptionDataChanged()
                    await session.reload(using: services)
                }
            }
        }
        .navigationTitle(destination.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                }
                .help("设置")
                .accessibilityIdentifier("open-settings")
            }
        }
    }
}

private enum DetailViewError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? { "订阅数据库尚未就绪。" }
}
