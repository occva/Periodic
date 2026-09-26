import SwiftUI

struct SubscriptionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle

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
                subscription: subscription,
                canConfirmRenewal: renewalPreview != nil,
                isConfirmingRenewal: isConfirmingRenewal,
                onMarkNotRenewed: { isPresentingNonRenewalConfirmation = true },
                onConfirmRenewal: { isPresentingRenewalOptions = true },
                onEditSubscription: onEditSubscription
            )
            Divider()
            SubscriptionPeriodHistoryView(
                rows: rows,
                draft: $periodDraft,
                isLoading: isLoading,
                isSaving: isSavingPeriod,
                isDeleting: isDeletingPeriod,
                onCreate: beginPeriodCreation,
                onEdit: beginPeriodEditing,
                onSave: savePeriodEditing,
                onCancel: cancelPeriodEditing,
                onDelete: { periodPendingDeletion = $0 }
            )
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
