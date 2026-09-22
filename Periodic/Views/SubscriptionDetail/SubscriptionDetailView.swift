import SwiftUI

struct SubscriptionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle

    let subscription: SubscriptionDTO
    let onEditSubscription: @MainActor () -> Void
    let loadPeriods: @MainActor (UUID) async throws -> [SubscriptionPeriodDTO]
    let addPeriod: @MainActor (SubscriptionPeriodAddInput) async throws -> Void
    let updatePeriod: @MainActor (SubscriptionPeriodUpdateInput) async throws -> Void

    @State private var periods: [SubscriptionPeriodDTO] = []
    @State private var isLoading = false
    @State private var periodDraft: SubscriptionPeriodDraft?
    @State private var isSavingPeriod = false
    @State private var error: PresentedError?

    private var item: SubscriptionListItem { SubscriptionListItem(dto: subscription) }
    private var rows: [SubscriptionPeriodRow] {
        var result = periods.enumerated().map { index, period in
            SubscriptionPeriodRow(
                id: period.id,
                sequence: index + 1,
                period: period
            )
        }
        if let periodDraft, periodDraft.isCreating {
            result.append(
                SubscriptionPeriodRow(
                    id: periodDraft.id,
                    sequence: periods.count + 1,
                    period: nil
                )
            )
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            history
            Divider()
            HStack {
                Text("共 \(periods.count) 次")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("添加记录", systemImage: "plus") {
                    beginPeriodCreation()
                }
                .disabled(periodDraft != nil || isSavingPeriod || isLoading)

                Button(dismissButtonTitle) {
                    if periodDraft == nil {
                        dismiss()
                    } else {
                        cancelPeriodEditing()
                    }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSavingPeriod)
                .buttonStyle(.glass)
            }
            .padding(16)
        }
        .frame(minWidth: 900, idealWidth: 1_000, minHeight: 460, idealHeight: 560)
        .task(id: subscription.id) { await reload() }
        .errorAlert($error)
        .accessibilityIdentifier("subscription-detail")
    }

    private var header: some View {
        HStack(spacing: 16) {
            ServiceIconView(
                iconResourceName: subscription.iconResourceName,
                iconURLString: subscription.iconURLString,
                fallbackSeed: subscription.name,
                size: 56
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(subscription.name)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Text(item.managementStatus)
                    Text(subscription.category.title)
                    Text(item.expiryDate)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑订阅", systemImage: "pencil") {
                onEditSubscription()
            }
            .buttonStyle(.glass)
        }
        .padding(20)
    }

    @ViewBuilder
    private var history: some View {
        if isLoading {
            ProgressView("正在读取订阅次数…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("暂无订阅次数", systemImage: "calendar.badge.clock")
            } description: {
                Text("具有完整开始和结束日期的新订阅会在这里记录首次周期，也可以手动添加记录。")
            } actions: {
                Button("添加记录", systemImage: "plus") {
                    beginPeriodCreation()
                }
                .buttonStyle(.glass)
            }
        } else {
            Table(rows) {
                TableColumn("订阅次数") { row in
                    Text("\(row.sequence)")
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if let period = row.period { beginPeriodEditing(period) }
                        }
                }
                .width(min: 70, ideal: 90)

                TableColumn("周期") { row in
                    if isEditing(row) {
                        Picker(
                            "周期",
                            selection: draftBinding(\.kind, fallback: .monthly)
                        ) {
                            ForEach(SubscriptionPeriodKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    } else {
                        Text(row.cycleTitle)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if let period = row.period { beginPeriodEditing(period) }
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
                        Text(row.period?.start.displayText ?? "—")
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if let period = row.period { beginPeriodEditing(period) }
                            }
                    }
                }
                .width(min: 120, ideal: 145)

                TableColumn("结束时间") { row in
                    if isEditing(row) {
                        if periodDraft?.kind == .lifetime {
                            Text("永久有效")
                                .foregroundStyle(.secondary)
                        } else {
                            DatePicker(
                                "结束时间",
                                selection: draftBinding(\.endDate, fallback: Date()),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .controlSize(.small)
                        }
                    } else {
                        Text(row.period?.end?.displayText ?? "永久有效")
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if let period = row.period { beginPeriodEditing(period) }
                            }
                    }
                }
                .width(min: 120, ideal: 145)

                TableColumn("金额") { row in
                    if isEditing(row) {
                        HStack(spacing: 6) {
                            TextField(
                                "金额",
                                text: draftBinding(\.amountText, fallback: "")
                            )
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()

                            Picker(
                                "币种",
                                selection: draftBinding(\.currency, fallback: .cny)
                            ) {
                                ForEach(CurrencyCode.allCases) { currency in
                                    Text(currency.rawValue).tag(currency)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 70)
                        }
                    } else {
                        Text(
                            row.period?.money.displayText(style: currencyDisplayStyle) ?? "—"
                        )
                            .monospacedDigit()
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if let period = row.period { beginPeriodEditing(period) }
                            }
                    }
                }
                .width(min: 170, ideal: 190)

                TableColumn("操作") { row in
                    if isEditing(row) {
                        HStack(spacing: 6) {
                            Button {
                                savePeriodEditing()
                            } label: {
                                Label("保存", systemImage: "checkmark")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(isSavingPeriod)
                            .help("保存修改")

                            Button {
                                cancelPeriodEditing()
                            } label: {
                                Label("取消", systemImage: "xmark")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .disabled(isSavingPeriod)
                            .help("取消修改")
                        }
                    } else {
                        if let period = row.period {
                            Button("编辑") {
                                beginPeriodEditing(period)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(periodDraft != nil)
                            .help("直接编辑此行")
                        }
                    }
                }
                .width(min: 64, ideal: 72, max: 80)
            }
        }
    }

    private func isEditing(_ row: SubscriptionPeriodRow) -> Bool {
        periodDraft?.id == row.id
    }

    private var dismissButtonTitle: String {
        guard let periodDraft else { return AppLocalization.string("关闭") }
        return AppLocalization.string(periodDraft.isCreating ? "取消添加" : "取消编辑")
    }

    private func beginPeriodCreation() {
        guard periodDraft == nil else { return }
        periodDraft = SubscriptionPeriodDraft(subscription: subscription)
    }

    private func beginPeriodEditing(_ period: SubscriptionPeriodDTO) {
        guard periodDraft == nil || periodDraft?.id == period.id else { return }
        periodDraft = SubscriptionPeriodDraft(period: period)
    }

    private func cancelPeriodEditing() {
        periodDraft = nil
        error = nil
    }

    private func savePeriodEditing() {
        guard let periodDraft else { return }
        do {
            if periodDraft.isCreating {
                let input = try periodDraft.addInput(
                    subscriptionID: subscription.id,
                    expectedSubscriptionRevision: subscription.revision
                )
                persistPeriod { try await addPeriod(input) }
            } else {
                let input = try periodDraft.updateInput(
                    expectedSubscriptionRevision: subscription.revision
                )
                persistPeriod { try await updatePeriod(input) }
            }
        } catch {
            self.error = PresentedError(error, title: "请检查周期记录")
        }
    }

    private func persistPeriod(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        isSavingPeriod = true
        Task { @MainActor in
            do {
                try await operation()
                periodDraft = nil
                isSavingPeriod = false
                await reload()
            } catch {
                self.error = PresentedError(error, title: "无法保存周期记录")
                isSavingPeriod = false
            }
        }
    }

    private func draftBinding<Value>(
        _ keyPath: WritableKeyPath<SubscriptionPeriodDraft, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { periodDraft?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard var draft = periodDraft else { return }
                draft[keyPath: keyPath] = newValue
                periodDraft = draft
            }
        )
    }

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            periods = try await loadPeriods(subscription.id)
            error = nil
        } catch {
            self.error = PresentedError(error, title: "无法读取订阅详情")
        }
    }
}
