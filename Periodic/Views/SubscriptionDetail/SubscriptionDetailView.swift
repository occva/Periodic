import SwiftUI

struct SubscriptionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""

    let subscription: SubscriptionDTO
    let onEditSubscription: @MainActor () -> Void
    let loadPeriods: @MainActor (UUID) async throws -> [SubscriptionPeriodDTO]
    let addPeriod: @MainActor (SubscriptionPeriodAddInput) async throws -> Void
    let updatePeriod: @MainActor (SubscriptionPeriodUpdateInput) async throws -> Void
    let deletePeriod: @MainActor (SubscriptionPeriodDeleteInput) async throws -> Void
    let confirmAutomaticRenewal: @MainActor (SubscriptionRenewalRequest) async throws -> Void
    let markAutomaticRenewalNotRenewed: @MainActor (
        SubscriptionNonRenewalRequest
    ) async throws -> Void

    @State private var periods: [SubscriptionPeriodDTO] = []
    @State private var isLoading = false
    @State private var periodDraft: SubscriptionPeriodDraft?
    @State private var isSavingPeriod = false
    @State private var periodPendingDeletion: SubscriptionPeriodDTO?
    @State private var isDeletingPeriod = false
    @State private var isConfirmingRenewal = false
    @State private var isPresentingRenewalOptions = false
    @State private var isPresentingNonRenewalConfirmation = false
    @State private var renewalEditorPreview: SubscriptionRenewalPreview?
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
                if !rows.isEmpty {
                    Button("添加记录", systemImage: "plus") {
                        beginPeriodCreation()
                    }
                    .disabled(
                        periodDraft != nil || isSavingPeriod || isDeletingPeriod || isLoading
                    )
                }

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
        .frame(width: 960, height: 560)
        .presentationSizing(.fitted)
        .task(id: subscription.id) { await reload() }
        .errorAlert($error)
        .confirmationDialog(
            "选择续费方式",
            isPresented: $isPresentingRenewalOptions,
            titleVisibility: .visible
        ) {
            Button("按当前周期续费") { confirmRenewalWithCurrentTerms() }
            Button("自定义续费…") { renewalEditorPreview = renewalPreview }
            Button("取消", role: .cancel) {}
        } message: {
            if let renewalPreview {
                Text(String(
                    format: AppLocalization.string("当前方案为 %@，%@。"),
                    renewalCycleTitle,
                    renewalPreview.money.displayText(style: currencyDisplayStyle)
                ))
            }
        }
        .confirmationDialog(
            "确认本期未续费？",
            isPresented: $isPresentingNonRenewalConfirmation,
            titleVisibility: .visible
        ) {
            Button("标记未续费", role: .destructive) { markAsNotRenewed() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将关闭服务商自动续费并保留当前到期状态，不会新增周期记录。")
        }
        .sheet(item: $renewalEditorPreview) { preview in
            SubscriptionRenewalEditorView(
                preview: preview,
                confirmRenewal: confirmAutomaticRenewal,
                onConfirmed: { await reload() }
            )
        }
        .confirmationDialog(
            "删除这条周期记录？",
            isPresented: Binding(
                get: { periodPendingDeletion != nil },
                set: { if !$0 { periodPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: periodPendingDeletion
        ) { period in
            Button("删除周期记录", role: .destructive) {
                delete(period)
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("此操作只删除历史记录，不会修改订阅当前的开始日期或到期日。")
        }
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
            if subscription.automaticallyRenews {
                if renewalPreview != nil {
                    Button("未续费", systemImage: "xmark") {
                        isPresentingNonRenewalConfirmation = true
                    }
                    .disabled(isConfirmingRenewal)
                    .buttonStyle(.glass)

                    Button("已续费", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                        isPresentingRenewalOptions = true
                    }
                    .disabled(isConfirmingRenewal)
                    .buttonStyle(.glassProminent)
                    .accessibilityHint("更新当前周期并添加一条续费周期记录")
                } else {
                    Label("服务商自动续费", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .foregroundStyle(.secondary)
                }
            }
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
                Text("周期订阅具有完整开始和结束日期时会记录首次周期，也可以手动添加记录。")
            } actions: {
                Button("添加记录", systemImage: "plus") {
                    beginPeriodCreation()
                }
                .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        DatePicker(
                            "结束时间",
                            selection: draftBinding(\.endDate, fallback: Date()),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .controlSize(.small)
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
                                ForEach(CurrencyPreferences.availableCurrencies(
                                    from: selectedCurrenciesRaw,
                                    including: periodDraft?.currency
                                )) { currency in
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
                            HStack(spacing: 8) {
                                Button("编辑", systemImage: "pencil") {
                                    beginPeriodEditing(period)
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .help("编辑周期记录")

                                Button("删除", systemImage: "trash", role: .destructive) {
                                    periodPendingDeletion = period
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .help("删除周期记录")
                            }
                            .disabled(periodDraft != nil || isDeletingPeriod)
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

    private func delete(_ period: SubscriptionPeriodDTO) {
        isDeletingPeriod = true
        let input = SubscriptionPeriodDeleteInput(
            original: period,
            expectedSubscriptionRevision: subscription.revision
        )
        Task { @MainActor in
            do {
                try await deletePeriod(input)
                periodPendingDeletion = nil
                isDeletingPeriod = false
                await reload()
            } catch {
                self.error = PresentedError(error, title: "无法删除周期记录")
                isDeletingPeriod = false
            }
        }
    }

    private var renewalPreview: SubscriptionRenewalPreview? {
        try? SubscriptionRenewalRule.preview(
            subscription: subscription,
            referenceDate: .today
        )
    }

    private var renewalCycleTitle: String {
        guard let renewalPreview else { return AppLocalization.string("自定义") }
        return BillingCycle(rawValue: renewalPreview.cycleMonths)?.title
            ?? AppLocalization.string("自定义")
    }

    private func confirmRenewalWithCurrentTerms() {
        guard let renewalPreview else { return }
        isConfirmingRenewal = true
        let request = SubscriptionRenewalRequest(
            subscriptionID: subscription.id,
            expectedRevision: renewalPreview.expectedRevision,
            expectedExpiry: renewalPreview.previousExpiry,
            cycleMonths: renewalPreview.cycleMonths,
            money: renewalPreview.money
        )
        Task { @MainActor in
            do {
                try await confirmAutomaticRenewal(request)
                isConfirmingRenewal = false
                await reload()
            } catch {
                self.error = PresentedError(error, title: "无法确认续费")
                isConfirmingRenewal = false
            }
        }
    }

    private func markAsNotRenewed() {
        guard let renewalPreview else { return }
        isConfirmingRenewal = true
        let request = SubscriptionNonRenewalRequest(
            subscriptionID: subscription.id,
            expectedRevision: renewalPreview.expectedRevision,
            expectedExpiry: renewalPreview.previousExpiry
        )
        Task { @MainActor in
            do {
                try await markAutomaticRenewalNotRenewed(request)
                isConfirmingRenewal = false
                await reload()
            } catch {
                self.error = PresentedError(error, title: "无法标记未续费")
                isConfirmingRenewal = false
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
