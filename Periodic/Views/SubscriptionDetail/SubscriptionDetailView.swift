import SwiftUI

private enum SubscriptionDetailSection: String, CaseIterable, Identifiable {
    case periods
    case activity
    case sharing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .periods: AppLocalization.string("周期")
        case .activity: AppLocalization.string("动态")
        case .sharing: AppLocalization.string("拼车")
        }
    }
}

struct SubscriptionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle

    let subscription: SubscriptionDTO
    let onEditSubscription: @MainActor () -> Void
    let loadDetail: @MainActor (UUID) async throws -> SubscriptionDetailSnapshot
    let addPeriod: @MainActor (SubscriptionPeriodAddInput) async throws -> Void
    let updatePeriod: @MainActor (SubscriptionPeriodUpdateInput) async throws -> Void
    let deletePeriod: @MainActor (SubscriptionPeriodDeleteInput) async throws -> Void
    let addPayment: @MainActor (SubscriptionPaymentAddInput) async throws -> Void
    let updatePayment: @MainActor (SubscriptionPaymentUpdateInput) async throws -> Void
    let deletePayment: @MainActor (SubscriptionPaymentDeleteInput) async throws -> Void
    let confirmAutomaticRenewal: @MainActor (SubscriptionRenewalRequest) async throws -> Void
    let markAutomaticRenewalNotRenewed: @MainActor (
        SubscriptionNonRenewalRequest
    ) async throws -> Void

    @State private var periods: [SubscriptionPeriodDTO] = []
    @State private var payments: [SubscriptionPaymentDTO] = []
    @State private var loadedSubscription: SubscriptionDTO?
    @State private var selectedSection = SubscriptionDetailSection.periods
    @State private var isLoading = false
    @State private var reloadGeneration = 0
    @State private var periodDraft: SubscriptionPeriodDraft?
    @State private var isEditingSharing = false
    @State private var isSavingPeriod = false
    @State private var periodPendingDeletion: SubscriptionPeriodDTO?
    @State private var isDeletingPeriod = false
    @State private var paymentDraft: SubscriptionPaymentDraft?
    @State private var paymentPendingDeletion: SubscriptionPaymentDTO?
    @State private var isDeletingPayment = false
    @State private var isConfirmingRenewal = false
    @State private var isPresentingRenewalOptions = false
    @State private var isPresentingNonRenewalConfirmation = false
    @State private var renewalEditorPreview: SubscriptionRenewalPreview?
    @State private var error: PresentedError?

    private var currentSubscription: SubscriptionDTO {
        loadedSubscription ?? subscription
    }

    private var canShowSharing: Bool {
        currentSubscription.sharing != nil || periods.contains { $0.sharing != nil } || isEditingSharing
    }

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
            SubscriptionDetailHeaderView(
                subscription: currentSubscription,
                canConfirmRenewal: renewalPreview != nil,
                isConfirmingRenewal: isConfirmingRenewal,
                onMarkNotRenewed: { isPresentingNonRenewalConfirmation = true },
                onConfirmRenewal: { isPresentingRenewalOptions = true },
                onEditSubscription: onEditSubscription
            )
            .disabled(periodDraft != nil || isSavingPeriod || isDeletingPeriod || isDeletingPayment || isEditingSharing)
            Divider()
            HStack {
                Picker("详情内容", selection: $selectedSection) {
                    ForEach(SubscriptionDetailSection.allCases.filter {
                        $0 != .sharing || canShowSharing
                    }) { section in
                        Text(section.title).tag(section)
                            .accessibilityIdentifier("subscription-detail-section-" + section.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                if selectedSection != .sharing {
                    Text(summaryTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                primaryHistoryAction
                    .buttonStyle(.glass)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .disabled(
                periodDraft != nil || isSavingPeriod || isDeletingPeriod || isDeletingPayment || isEditingSharing
            )
            Divider()
            detailContent
            if !isEditingSharing {
                Divider()
                HStack {
                    if periodDraft != nil {
                        Text("修改尚未保存")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

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
        }
        .frame(minWidth: 760, idealWidth: 960, minHeight: 520, idealHeight: 620)
        .presentationSizing(.fitted)
        .interactiveDismissDisabled(isEditingSharing || periodDraft != nil)
        .task(id: subscription.id) { await reload() }
        .onChange(of: subscription.revision) { _, newRevision in
            guard loadedSubscription?.revision != newRevision else { return }
            Task { @MainActor in await reload() }
        }
        .onChange(of: canShowSharing) { _, hasSharing in
            if !hasSharing, selectedSection == .sharing {
                selectedSection = .periods
            }
        }
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
                    renewalPreview.defaultPaymentMoney.displayText(style: currencyDisplayStyle)
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
        .sheet(item: $paymentDraft) { draft in
            SubscriptionPaymentEditorView(draft: draft, periods: periods) { savedDraft in
                if savedDraft.isCreating {
                    let input = try savedDraft.addInput(
                        subscriptionID: currentSubscription.id,
                        expectedSubscriptionRevision: currentSubscription.revision,
                        periods: periods
                    )
                    try await addPayment(input)
                } else {
                    let input = try savedDraft.updateInput(
                        expectedSubscriptionRevision: currentSubscription.revision,
                        periods: periods
                    )
                    try await updatePayment(input)
                }
                await reload()
            }
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
            Text("此操作只删除周期记录并解除消费关联，不会删除消费，也不会修改订阅当前的开始日期或到期日。")
        }
        .confirmationDialog(
            "删除这条消费记录？",
            isPresented: Binding(
                get: { paymentPendingDeletion != nil },
                set: { if !$0 { paymentPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: paymentPendingDeletion
        ) { payment in
            Button("删除消费记录", role: .destructive) {
                delete(payment)
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("删除后实际支出会同步更新；关联的周期记录仍会保留。")
        }
        .accessibilityIdentifier("subscription-detail")
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .periods:
            SubscriptionPeriodHistoryView(
                rows: rows,
                draft: $periodDraft,
                isLoading: isLoading,
                isSaving: isSavingPeriod,
                isDeleting: isDeletingPeriod,
                onEdit: beginPeriodEditing,
                onSave: savePeriodEditing,
                onCancel: cancelPeriodEditing,
                onDelete: { periodPendingDeletion = $0 }
            )
        case .sharing:
            SubscriptionSharingPeriodsView(
                subscription: currentSubscription,
                periods: periods,
                isLoading: isLoading,
                isEditing: $isEditingSharing,
                addPeriod: addPeriod,
                updatePeriod: updatePeriod,
                onSaved: { await reload() }
            )
        case .activity:
            SubscriptionActivityView(
                payments: payments,
                periods: periods,
                isLoading: isLoading,
                isDeleting: isDeletingPayment,
                onEdit: { paymentDraft = SubscriptionPaymentDraft(payment: $0) },
                onDelete: { paymentPendingDeletion = $0 }
            )
        }
    }

    private var summaryTitle: String {
        switch selectedSection {
        case .periods: String(format: AppLocalization.string("共 %d 次"), periods.count)
        case .sharing: currentSubscription.sharing?.summary ?? ""
        case .activity: String(format: AppLocalization.string("共 %d 笔消费"), payments.count)
        }
    }

    @ViewBuilder
    private var primaryHistoryAction: some View {
        switch selectedSection {
        case .periods:
            Button("添加周期") { beginPeriodCreation() }
                .disabled(
                    periodDraft != nil || isSavingPeriod || isDeletingPeriod || isLoading
                )
        case .sharing:
            if currentSubscription.sharing != nil {
                Button("编辑当前方案") { onEditSubscription() }
            }
        case .activity:
            Button("记录消费") {
                paymentDraft = SubscriptionPaymentDraft(subscription: currentSubscription)
            }
            .disabled(isDeletingPayment || isLoading)
        }
    }

    private var dismissButtonTitle: String {
        guard let periodDraft else { return AppLocalization.string("关闭") }
        return AppLocalization.string(periodDraft.isCreating ? "取消添加" : "取消编辑")
    }

    private func beginPeriodCreation() {
        guard periodDraft == nil else { return }
        periodDraft = SubscriptionPeriodDraft(subscription: currentSubscription)
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
                    subscriptionID: currentSubscription.id,
                    expectedSubscriptionRevision: currentSubscription.revision
                )
                persistPeriod { try await addPeriod(input) }
            } else {
                let input = try periodDraft.updateInput(
                    expectedSubscriptionRevision: currentSubscription.revision
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
            expectedSubscriptionRevision: currentSubscription.revision
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

    private func delete(_ payment: SubscriptionPaymentDTO) {
        isDeletingPayment = true
        let input = SubscriptionPaymentDeleteInput(
            original: payment,
            expectedSubscriptionRevision: currentSubscription.revision
        )
        Task { @MainActor in
            do {
                try await deletePayment(input)
                paymentPendingDeletion = nil
                isDeletingPayment = false
                await reload()
            } catch {
                self.error = PresentedError(error, title: "无法删除消费记录")
                isDeletingPayment = false
            }
        }
    }

    private var renewalPreview: SubscriptionRenewalPreview? {
        try? SubscriptionRenewalRule.preview(
            subscription: currentSubscription,
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
            subscriptionID: currentSubscription.id,
            expectedRevision: renewalPreview.expectedRevision,
            expectedExpiry: renewalPreview.previousExpiry,
            cycleMonths: renewalPreview.cycleMonths,
            quotedMoney: renewalPreview.money,
            paymentDate: .today,
            paymentMoney: renewalPreview.defaultPaymentMoney,
            paymentNote: ""
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
            subscriptionID: currentSubscription.id,
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

    @MainActor
    private func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        isLoading = true
        defer {
            if generation == reloadGeneration {
                isLoading = false
            }
        }
        do {
            let snapshot = try await loadDetail(subscription.id)
            guard generation == reloadGeneration else { return }
            loadedSubscription = snapshot.subscription
            periods = snapshot.periods
            payments = snapshot.payments
            error = nil
        } catch {
            guard generation == reloadGeneration else { return }
            self.error = PresentedError(error, title: "无法读取订阅详情")
        }
    }
}
