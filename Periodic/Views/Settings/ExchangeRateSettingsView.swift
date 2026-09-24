import SwiftUI

struct ExchangeRateSettingsView: View {
    private enum CurrencyScope: String, CaseIterable, Identifiable {
        case selected
        case all

        var id: String { rawValue }
        var title: String {
            AppLocalization.string(self == .selected ? "已选" : "全部")
        }
    }

    @Environment(AppServices.self) private var services
    @AppStorage(PreferenceKey.defaultCurrency) private var defaultCurrency = CurrencyCode.cny
    @AppStorage(PreferenceKey.exchangeRateBaseCurrency) private var baseCurrency = CurrencyCode.cny
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""
    @State private var feature = ExchangeRateSettingsFeature()
    @State private var searchText = ""
    @State private var scope = CurrencyScope.selected

    private var selectedCurrencies: [CurrencyCode] {
        CurrencyPreferences.selectedCurrencies(from: selectedCurrenciesRaw)
    }

    private var visibleRows: [ExchangeRateRow] {
        let selected = Set(selectedCurrencies.map(\.rawValue))
        return feature.catalog?.rows.filter {
            $0.matches(searchText) && (scope == .all || selected.contains($0.currencyCode))
        } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            status
            rateTable
        }
        .padding(16)
        .task(id: baseCurrency) {
            await feature.load(using: services.exchangeRates, baseCurrency: baseCurrency)
        }
    }

    private var controls: some View {
        HStack {
            Picker("范围", selection: $scope) {
                ForEach(CurrencyScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 110)

            Picker("基准货币", selection: $baseCurrency) {
                ForEach(selectedCurrencies) { currency in
                    Text(currency.rawValue).tag(currency)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            TextField("搜索币种", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
                .accessibilityIdentifier("exchange-rate-search-field")

            Spacer()

            Button {
                Task {
                    await feature.refresh(
                        using: services.exchangeRates,
                        baseCurrency: baseCurrency
                    )
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(feature.isLoading)
            .keyboardShortcut("r", modifiers: [.command])
            .accessibilityIdentifier("exchange-rate-refresh-button")
        }
    }

    @ViewBuilder
    private var status: some View {
        if let catalog = feature.catalog {
            HStack(spacing: 6) {
                Text("Frankfurter v2")
                Text("最新数据日期 \(catalog.latestDate)")
                Text("本地更新 \(catalog.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                if catalog.isStale {
                    Text("缓存数据")
                }
                Spacer()
                Text("共 \(catalog.rows.count) 种")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        } else if feature.isLoading {
            ProgressView("正在下载完整汇率列表…")
                .controlSize(.small)
        } else {
            Text("尚无本地汇率数据")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        if let error = feature.error {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
        }
    }

    private var rateTable: some View {
        Table(visibleRows) {
            TableColumn("") { row in
                if let currency = CurrencyCode(rawValue: row.currencyCode) {
                    Toggle("选择 \(row.currencyCode)", isOn: selectionBinding(for: currency))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .disabled(isOnlySelectedCurrency(currency))
                }
            }
            .width(28)

            TableColumn("币种") { row in
                Text(row.currencyCode)
                    .font(.body.monospaced())
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("名称") { row in
                Text(row.localizedName)
            }

            TableColumn("数据日期") { row in
                Text(row.date)
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 100, max: 110)

            TableColumn("1 \(baseCurrency.rawValue) 可兑换") { row in
                Text(formatRate(row.rate))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 130, ideal: 170)
        }
        .overlay {
            if feature.catalog != nil, visibleRows.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .accessibilityIdentifier("exchange-rate-table")
    }

    private func formatRate(_ rate: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSDecimalNumber(decimal: rate))
            ?? NSDecimalNumber(decimal: rate).stringValue
    }

    private func selectionBinding(for currency: CurrencyCode) -> Binding<Bool> {
        Binding(
            get: { selectedCurrencies.contains(currency) },
            set: { isSelected in
                var updated = Set(selectedCurrencies)
                if isSelected {
                    updated.insert(currency)
                } else if updated.count > 1 {
                    updated.remove(currency)
                }
                selectedCurrenciesRaw = CurrencyPreferences.storedValue(for: updated)
                if !updated.contains(baseCurrency), let replacement = updated.sorted(by: {
                    $0.rawValue < $1.rawValue
                }).first {
                    baseCurrency = replacement
                }
                if !updated.contains(defaultCurrency), let replacement = updated.sorted(by: {
                    $0.rawValue < $1.rawValue
                }).first {
                    defaultCurrency = replacement
                }
            }
        )
    }

    private func isOnlySelectedCurrency(_ currency: CurrencyCode) -> Bool {
        selectedCurrencies.count == 1 && selectedCurrencies.contains(currency)
    }
}
