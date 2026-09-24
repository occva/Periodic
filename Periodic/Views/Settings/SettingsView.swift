import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }

            ExchangeRateSettingsView()
                .tabItem { Label("汇率", systemImage: "arrow.left.arrow.right") }

            DataSettingsView()
                .tabItem { Label("数据", systemImage: "externaldrive") }
        }
        .frame(width: 640, height: 560)
        .onAppear {
            AppLog.lifecycle.info("Settings window appeared")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppServices(inMemory: true))
}
