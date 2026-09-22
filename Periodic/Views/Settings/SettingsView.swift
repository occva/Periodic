import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 500, height: 390)
        .onAppear {
            AppLog.lifecycle.info("Settings window appeared")
        }
    }
}

#Preview {
    SettingsView()
}
