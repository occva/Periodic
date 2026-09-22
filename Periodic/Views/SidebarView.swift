import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppDestination?

    var body: some View {
        List(AppDestination.allCases, selection: $selection) { destination in
            Label(destination.title, systemImage: destination.symbolName)
                .tag(destination)
                .accessibilityIdentifier("destination-\(destination.rawValue)")
        }
        .listStyle(.sidebar)
        .navigationTitle(AppConfiguration.displayName)
    }
}
