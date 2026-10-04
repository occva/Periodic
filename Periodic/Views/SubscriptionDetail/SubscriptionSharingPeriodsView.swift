import SwiftUI

struct SubscriptionSharingPeriodsView: View {
    let subscription: SubscriptionDTO
    let periods: [SubscriptionPeriodDTO]
    let isLoading: Bool
    @Binding var isEditing: Bool
    let addPeriod: @MainActor (SubscriptionPeriodAddInput) async throws -> Void
    let updatePeriod: @MainActor (SubscriptionPeriodUpdateInput) async throws -> Void
    let onSaved: @MainActor () async -> Void

    @State private var state = SubscriptionSharingPeriodEditorState()

    private var sharedPeriods: [SubscriptionPeriodDTO] {
        periods.filter { $0.subscriptionID == subscription.id && $0.sharing != nil }
    }

    private var selectedPeriod: SubscriptionPeriodDTO? {
        guard case .period(let id) = state.selection else { return nil }
        return sharedPeriods.first { $0.id == id }
    }

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            controls
            if let session = state.editorSession {
                @Bindable var session = session
                SubscriptionSharingPeriodEditor(draft: $session.draft)
                    .id(ObjectIdentifier(session))
                    .disabled(state.isSaving)
                editingActions
            } else if let period = selectedPeriod, let plan = period.sharing {
                SubscriptionSharingView(plan: plan, myMoney: period.money)
            } else if state.selection == .current, let plan = subscription.sharing {
                SubscriptionSharingView(plan: plan, myMoney: subscription.money)
            } else if isLoading {
                ProgressView("正在读取拼车周期…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("暂无拼车周期", systemImage: "person.2")
            }
        }
        .onChange(of: state.editorSession != nil) { _, editing in isEditing = editing }
        .onChange(of: periods, initial: true) { _, _ in reconcileSelection() }
        .onChange(of: isLoading) { _, loading in if !loading { reconcileSelection() } }
        .errorAlert($state.error)
        .confirmationDialog(
            "本期日期与已有周期重叠，仍要保存？",
            isPresented: $state.isPresentingOverlapConfirmation,
            titleVisibility: .visible
        ) {
            Button("继续保存") { save(confirmingOverlap: true) }
            Button("返回修改", role: .cancel) {}
        } message: {
            Text("会保留两条独立周期，不合并或覆盖已有记录。")
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if let session = state.editorSession {
                Text(session.draft.isCreating ? "添加周期" : "编辑本期")
                    .font(.headline)
                Spacer()
            } else {
                Spacer(minLength: 0)
                Picker("周期", selection: $state.selection) {
                    if subscription.sharing != nil {
                        Text("当前方案").tag(SubscriptionSharingPeriodSelection.current)
                    }
                    ForEach(sharedPeriods) { period in
                        Text(periodTitle(period)).tag(SubscriptionSharingPeriodSelection.period(period.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)
                Button("添加周期") {
                    state.beginAdding(subscription: subscription, periods: periods)
                }
                if let selectedPeriod {
                    Button("编辑本期") {
                        state.beginEditing(period: selectedPeriod, expectedRevision: subscription.revision)
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .disabled(isLoading || state.isSaving)
    }

    private var editingActions: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Text("修改尚未保存")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if state.isSaving { ProgressView().controlSize(.small) }
                Button("取消") { state.cancelEditing() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .disabled(state.isSaving)
    }

    private func periodTitle(_ period: SubscriptionPeriodDTO) -> String {
        period.start.displayText + " – " + (period.end?.displayText ?? AppLocalization.string("永久有效"))
    }

    private func reconcileSelection() {
        guard !isLoading else { return }
        state.reconcileSelection(subscription: subscription, periods: periods)
    }

    private func save(confirmingOverlap: Bool = false) {
        Task { @MainActor in
            if await state.save(
                periods: periods,
                confirmingOverlap: confirmingOverlap,
                addPeriod: addPeriod,
                updatePeriod: updatePeriod,
                onSaved: onSaved
            ) { isEditing = false }
        }
    }
}
