import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: AppLocalization.string("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }

    fileprivate var localizationCode: String? {
        switch self {
        case .system: nil
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
    }
}

enum AppLocalization {
    static func string(_ key: String) -> String {
        activeBundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static var activeBundle: Bundle {
        let rawValue = UserDefaults.standard.string(forKey: PreferenceKey.language)
        let language = rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .system
        guard let code = language.localizationCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

enum AppPreferenceValues {
    static var defaultCurrency: CurrencyCode {
        let rawValue = UserDefaults.standard.string(forKey: PreferenceKey.defaultCurrency)
        return rawValue.flatMap(CurrencyCode.init(rawValue:)) ?? .cny
    }

    static var currencyDisplayStyle: CurrencyDisplayStyle {
        UserDefaults.standard.bool(forKey: PreferenceKey.usesCurrencySymbols)
            ? .symbol
            : .code
    }

    static var exchangeRateBaseCurrency: CurrencyCode {
        let rawValue = UserDefaults.standard.string(forKey: PreferenceKey.exchangeRateBaseCurrency)
        return rawValue.flatMap(CurrencyCode.init(rawValue:)) ?? .cny
    }
}
