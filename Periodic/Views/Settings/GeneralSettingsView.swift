import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(PreferenceKey.appearance) private var appearance = AppAppearance.system
    @AppStorage(PreferenceKey.language) private var language = AppLanguage.system
    @AppStorage(PreferenceKey.defaultCurrency) private var defaultCurrency = CurrencyCode.cny
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""
    @AppStorage(PreferenceKey.usesCurrencySymbols) private var usesCurrencySymbols = false
    @AppStorage(PreferenceKey.menuBarEnabled) private var menuBarEnabled = true
    @AppStorage(PreferenceKey.menuBarDueHorizon) private var menuBarDueHorizon =
        MenuBarPreferences.defaultDueHorizon.rawValue
    @AppStorage(PreferenceKey.menuBarShowsForecasts) private var menuBarShowsForecasts = true

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
                    ForEach(CurrencyPreferences.availableCurrencies(
                        from: selectedCurrenciesRaw,
                        including: defaultCurrency
                    )) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }

                Toggle("使用货币符号", isOn: $usesCurrencySymbols)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("currency-symbol-toggle")

                Text("关闭时显示 CNY 81.00；开启时显示 ¥81.00（人民币）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("默认货币用于新建订阅和模板；汇率页可单独选择换算基准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("货币显示只改变界面格式，不会修改已保存的币种或金额。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("菜单栏") {
                Toggle("在菜单栏显示 Periodic", isOn: $menuBarEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("menu-bar-enabled-toggle")

                Picker("默认临期范围", selection: $menuBarDueHorizon) {
                    ForEach(DueHorizon.allCases) { horizon in
                        Text(horizon.title).tag(horizon.rawValue)
                    }
                }
                .disabled(!menuBarEnabled)

                Toggle("显示预估金额", isOn: $menuBarShowsForecasts)
                    .toggleStyle(.switch)
                    .disabled(!menuBarEnabled)

                Text("关闭菜单栏项目后，仍可从 Dock、Spotlight 或 Finder 打开 Periodic。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("续费提醒") {
                LabeledContent("通知状态") {
                    Label(notificationStatusTitle, systemImage: notificationStatusSymbol)
                        .foregroundStyle(notificationStatusColor)
                }

                Text(notificationStatusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            menuBarDueHorizon = MenuBarPreferences.normalizedDueHorizonRawValue(menuBarDueHorizon)
        }
    }

    private var notificationStatusTitle: String {
        switch services.renewalNotifications.status {
        case .idle: AppLocalization.string("尚未检查")
        case let .ready(scheduledCount):
            AppLocalization.string(scheduledCount > 0 ? "已安排" : "已送达或无需重排")
        case .noAutomaticRenewals: AppLocalization.string("暂无提醒")
        case .denied: AppLocalization.string("通知已关闭")
        case .failed: AppLocalization.string("安排失败")
        }
    }

    private var notificationStatusSymbol: String {
        switch services.renewalNotifications.status {
        case .idle, .noAutomaticRenewals: "bell"
        case .ready: "bell.badge"
        case .denied: "bell.slash"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var notificationStatusColor: Color {
        switch services.renewalNotifications.status {
        case .denied, .failed: .orange
        default: .secondary
        }
    }

    private var notificationStatusDetail: String {
        switch services.renewalNotifications.status {
        case .idle:
            AppLocalization.string("打开主窗口后会检查自动续费提醒。")
        case let .ready(scheduledCount):
            if scheduledCount > 0 {
                String(
                    format: AppLocalization.string("已为 %d 项自动续费安排到期日确认提醒。"),
                    scheduledCount
                )
            } else {
                AppLocalization.string("今日提醒已处理；确认续费或修改订阅后，旧通知会自动清理。")
            }
        case .noAutomaticRenewals:
            AppLocalization.string("启用订阅的“自动续费”后，会在到期日提醒你确认。")
        case .denied:
            AppLocalization.string("Periodic 无法发送提醒。请在“系统设置 > 通知”中允许通知。")
        case .failed:
            AppLocalization.string("无法更新续费提醒。请稍后重新打开主窗口再试。")
        }
    }
}
