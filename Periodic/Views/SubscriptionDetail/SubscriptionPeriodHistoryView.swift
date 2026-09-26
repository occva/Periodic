import SwiftUI

struct SubscriptionPeriodHistoryView: View {
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""

    let rows: [SubscriptionPeriodRow]
    @Binding var draft: SubscriptionPeriodDraft?
    let isLoading: Bool
    let isSaving: Bool
    let isDeleting: Bool
    let onCreate: @MainActor () -> Void
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
            } actions: {
                Button("添加记录", systemImage: "plus", action: onCreate)
                    .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            historyTable
        }
    }

    private var historyTable: some View {
        Table(rows) {
            TableColumn("订阅次数") { row in
                editableText("\(row.sequence)", row: row)
            }
            .width(min: 70, ideal: 90)

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
                    editableText(row.cycleTitle, row: row)
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
                    editableText(row.period?.start.displayText ?? "—", row: row)
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

            TableColumn("金额") { row in
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
            .width(min: 170, ideal: 190)

            TableColumn("操作") { row in
                actions(for: row)
            }
            .width(min: 64, ideal: 72, max: 80)
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
                Button {
                    onSave()
                } label: {
                    Label("保存", systemImage: "checkmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSaving)
                .help("保存修改")

                Button {
                    onCancel()
                } label: {
                    Label("取消", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .disabled(isSaving)
                .help("取消修改")
            }
        } else if let period = row.period {
            HStack(spacing: 8) {
                Button("编辑", systemImage: "pencil") {
                    onEdit(period)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("编辑周期记录")

                Button("删除", systemImage: "trash", role: .destructive) {
                    onDelete(period)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
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
