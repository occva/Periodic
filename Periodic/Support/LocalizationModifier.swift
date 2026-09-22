import SwiftUI

struct LocalizationModifier: ViewModifier {
    @AppStorage(PreferenceKey.language) private var language = AppLanguage.system

    func body(content: Content) -> some View {
        content.environment(\.locale, language.locale)
    }
}
