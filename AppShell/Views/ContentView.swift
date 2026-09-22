import SwiftUI

struct ContentView: View {
    @SceneStorage("window.destination") private var destinationID = AppDestination.workspace.rawValue
    @SceneStorage("window.sidebarVisible") private var sidebarVisible = true

    private var selection: Binding<AppDestination?> {
        Binding(
            get: { AppDestination(rawValue: destinationID) ?? .workspace },
            set: { if let destination = $0 { destinationID = destination.rawValue } }
        )
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarVisible ? .all : .detailOnly },
            set: { sidebarVisible = $0 != .detailOnly }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView(selection: selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            DetailView(destination: selection.wrappedValue ?? .workspace)
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            AppLog.lifecycle.info("Main window appeared")
        }
    }
}

#Preview {
    ContentView()
        .environment(AppServices())
}
