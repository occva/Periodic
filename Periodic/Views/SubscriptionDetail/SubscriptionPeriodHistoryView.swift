import SwiftUI

struct SubscriptionPeriodHistoryView: View {
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""

    @State private var sharingPeriod: SubscriptionPeriodDTO?

    let rows: [SubscriptionPeriodRow]
    @Binding var draft: SubscriptionPeriodDraft?
    let isLoading: Bool
    let isSaving: Bool
    let isDeleting: Bool
    let onEdit: @MainActor (SubscriptionPeriodDTO) -> Void
    let onSave: @MainActor () -> Void
    let onCancel: @MainActor () -> Void
    let onDelete: @MainActor (SubscriptionPeriodDTO) -> Void

    var body: some View {
        if isLoading {
            ProgressView("正在读取订阅次数…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("暂无订阅次数", systemImage: "calendar.badge.clock")
            } description: {
                Text("周期订阅具有完整开始和结束日期时会记录首次周期，也可以手动添加记录。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            historyTable
                .sheet(item: $sharingPeriod) { period in
                    VStack {
                        Text("本期拼车价格").font(.title2)
                        Text(period.start.displayText + " – " + (period.end?.displayText ?? "—"))
                        if let plan = period.sharing {
                            SubscriptionSharingView(plan: plan, myMoney: period.money)
                        }
                        Button("关闭") { sharingPeriod = nil }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(20)
                    .frame(width: 560, height: 540)
                }
        }
    }

    private var historyTable: some View {
        Table(rows) {
            TableColumn("订阅次数") { row in
                editableText("\(row.sequence)", row: row)
            }
            .width(min: 50, ideal: 60)

            TableColumn("周期") { row in
                if isEditing(row) {
                    Picker("周期", selection: draftBinding(\.kind, fallback: .monthly)) {
                        ForEach(SubscriptionPeriodKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                } else {
                    VStack(alignment: .leading) {
                        editableText(row.cycleTitle, row: row)
                        if let period = row.period, period.sharing != nil {
                            Button("拼车价格") { sharingPeriod = period }
                                .buttonStyle(.link)
                        }
                    }
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn("开始时间") { row in
                if isEditing(row) {
                    DatePicker(
                        "开始时间",
                        selection: draftBinding(\.startDate, fallback: Date()),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .controlSize(.small)
                } else {
                    editableText(row.startTitle, row: row)
                }
            }
            .width(min: 120, ideal: 145)

            TableColumn("结束时间") { row in
                if isEditing(row) {
                    DatePicker(
                        "结束时间",
                        selection: draftBinding(\.endDate, fallback: Date()),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .controlSize(.small)
                } else {
                    editableText(row.period?.end?.displayText ?? "永久有效", row: row)
                }
            }
            .width(min: 120, ideal: 145)

            TableColumn("本期价格") { row in
                if isEditing(row) {
                    moneyEditor
                } else {
                    editableText(
                        row.period?.money.displayText(style: currencyDisplayStyle) ?? "—",
                        row: row
                    )
                    .monospacedDigit()
                }
            }
            .width(min: 140, ideal: 170)

            TableColumn("操作") { row in
                actions(for: row)
            }
            .width(min: 110, ideal: 120)
        }
    }

    private var moneyEditor: some View {
        HStack(spacing: 6) {
            TextField("金额", text: draftBinding(\.amountText, fallback: ""))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()

            Picker("币种", selection: draftBinding(\.currency, fallback: .cny)) {
                ForEach(CurrencyPreferences.availableCurrencies(
                    from: selectedCurrenciesRaw,
                    including: draft?.currency
                )) { currency in
                    Text(currency.rawValue).tag(currency)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 70)
        }
    }

    private func editableText(_ text: String, row: SubscriptionPeriodRow) -> some View {
        Text(text)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if let period = row.period {
                    onEdit(period)
                }
            }
    }

    @ViewBuilder
    private func actions(for row: SubscriptionPeriodRow) -> some View {
        if isEditing(row) {
            HStack(spacing: 6) {
                Button("保存", action: onSave)
                .buttonStyle(.borderless)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSaving)
                .help("保存修改")

                Button("取消", action: onCancel)
                .buttonStyle(.borderless)
                .disabled(isSaving)
                .help("取消修改")
            }
        } else if let period = row.period {
            HStack(spacing: 8) {
                Button("编辑") {
                    onEdit(period)
                }
                .buttonStyle(.borderless)
                .help("编辑周期记录")

                Button("删除", role: .destructive) {
                    onDelete(period)
                }
                .buttonStyle(.borderless)
                .help("删除周期记录")
            }
            .disabled(draft != nil || isDeleting)
        }
    }

    private func isEditing(_ row: SubscriptionPeriodRow) -> Bool {
        draft?.id == row.id
    }

    private func draftBinding<Value>(
        _ keyPath: WritableKeyPath<SubscriptionPeriodDraft, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard var updatedDraft = draft else { return }
                updatedDraft[keyPath: keyPath] = newValue
                draft = updatedDraft
            }
        )
    }
}
