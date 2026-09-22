import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(PreferenceKey.appearance) private var appearance = AppAppearance.system
    @AppStorage(PreferenceKey.language) private var language = AppLanguage.system
    @AppStorage(PreferenceKey.defaultCurrency) private var defaultCurrency = CurrencyCode.cny
    @AppStorage(PreferenceKey.usesCurrencySymbols) private var usesCurrencySymbols = false

    var body: some View {
        Form {
            Section("显示") {
                Picker("外观", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .accessibilityIdentifier("appearance-picker")
            }

            Section("语言与地区") {
                Picker("语言", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Picker("默认货币", selection: $defaultCurrency) {
                    ForEach(CurrencyCode.allCases) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }

                Toggle("使用货币符号", isOn: $usesCurrencySymbols)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("currency-symbol-toggle")

                Text("关闭时显示 CNY 81.00；开启时显示 ¥81.00（人民币）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("默认货币只用于新建订阅和模板，不会换算或修改已有金额。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("货币显示只改变界面格式，不会修改已保存的币种或金额。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
