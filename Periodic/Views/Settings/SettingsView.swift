import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 220)
        .onAppear {
            AppLog.lifecycle.info("Settings window appeared")
        }
    }
}

#Preview {
    SettingsView()
}
