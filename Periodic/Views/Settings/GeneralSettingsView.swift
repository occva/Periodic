import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(PreferenceKey.appearance) private var appearance = AppAppearance.system

    var body: some View {
        Form {
            Picker("外观", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .accessibilityIdentifier("appearance-picker")
        }
        .formStyle(.grouped)
    }
}
