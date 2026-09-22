import SwiftUI

private struct CurrencyDisplayStyleKey: EnvironmentKey {
    static let defaultValue = CurrencyDisplayStyle.code
}

extension EnvironmentValues {
    var currencyDisplayStyle: CurrencyDisplayStyle {
        get { self[CurrencyDisplayStyleKey.self] }
        set { self[CurrencyDisplayStyleKey.self] = newValue }
    }
}

struct CurrencyDisplayModifier: ViewModifier {
    @AppStorage(PreferenceKey.usesCurrencySymbols)
    private var usesCurrencySymbols = false

    func body(content: Content) -> some View {
        content.environment(
            \.currencyDisplayStyle,
            usesCurrencySymbols ? .symbol : .code
        )
    }
}
