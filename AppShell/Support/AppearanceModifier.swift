import SwiftUI

struct AppearanceModifier: ViewModifier {
    @AppStorage(PreferenceKey.appearance) private var appearance = AppAppearance.system

    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance.colorScheme)
    }
}
