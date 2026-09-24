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
    @AppStorage(PreferenceKey.defaultTimelineRange) private var defaultTimelineRange =
        TimelinePreferences.defaultRange.rawValue

    var body: some View {
        Form {
            Section("显示") {
                Picker("外观", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .accessibilityIdentifier("appearance-picker")

                Picker("默认时间轴范围", selection: $defaultTimelineRange) {
                    ForEach(TimelineRange.allCases) { range in
                        Text(range.title).tag(range.rawValue)
                    }
                }

                Text("新窗口会使用此范围；当前窗口已选择的范围保持不变。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("订阅提醒") {
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
            defaultTimelineRange = TimelinePreferences.normalizedRangeRawValue(
                defaultTimelineRange
            )
        }
    }

    private var notificationStatusTitle: String {
        switch services.subscriptionNotifications.status {
        case .idle: AppLocalization.string("尚未检查")
        case let .ready(scheduledCount, deferredCount, failedCount):
            if deferredCount > 0 || failedCount > 0 {
                AppLocalization.string("部分待重试")
            } else {
                AppLocalization.string(scheduledCount > 0 ? "已安排" : "已送达或无需重排")
            }
        case .noReminders: AppLocalization.string("暂无提醒")
        case .denied: AppLocalization.string("通知已关闭")
        case .failed: AppLocalization.string("安排失败")
        }
    }

    private var notificationStatusSymbol: String {
        switch services.subscriptionNotifications.status {
        case .idle, .noReminders: "bell"
        case .ready: "bell.badge"
        case .denied: "bell.slash"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var notificationStatusColor: Color {
        switch services.subscriptionNotifications.status {
        case .denied, .failed: .orange
        default: .secondary
        }
    }

    private var notificationStatusDetail: String {
        switch services.subscriptionNotifications.status {
        case .idle:
            return AppLocalization.string("打开主窗口后会检查订阅提醒。")
        case let .ready(scheduledCount, deferredCount, failedCount):
            if deferredCount > 0 || failedCount > 0 {
                return String(
                    format: AppLocalization.string("已安排 %d 项，%d 项延后，%d 项失败。"),
                    scheduledCount,
                    deferredCount,
                    failedCount
                )
            } else if scheduledCount > 0 {
                return String(
                    format: AppLocalization.string("已安排 %d 项到期提醒。"),
                    scheduledCount
                )
            } else {
                return AppLocalization.string("今日提醒已处理；订阅日期或提醒设置变化后会自动重新核对。")
            }
        case .noReminders:
            return AppLocalization.string("启用“到期提醒”或“服务商自动续费”后，会在到期日发送提醒。")
        case .denied:
            return AppLocalization.string("Periodic 无法发送提醒。请在“系统设置 > 通知”中允许通知。")
        case .failed:
            return AppLocalization.string("无法更新订阅提醒。请稍后重新打开主窗口再试。")
        }
    }
}
