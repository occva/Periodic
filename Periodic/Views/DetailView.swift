import SwiftUI

struct DetailView: View {
    let destination: AppDestination

    var body: some View {
        Group {
            switch destination {
            case .workspace:
                WorkspaceView()
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
