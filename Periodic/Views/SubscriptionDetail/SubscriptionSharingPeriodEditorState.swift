import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionSharingPeriodEditorState {
    var selection = SubscriptionSharingPeriodSelection.current
    private(set) var editorSession: SubscriptionSharingPeriodEditorSession?
    var error: PresentedError?
    var isPresentingOverlapConfirmation = false
    private(set) var isSaving = false
    private var hasSelectedInitialPeriod = false

    func reconcileSelection(subscription: SubscriptionDTO, periods: [SubscriptionPeriodDTO]) {
        guard editorSession == nil else { return }
        let selectionExists: Bool
        switch selection {
        case .current: selectionExists = subscription.sharing != nil
        case .period(let id): selectionExists = periods.contains { $0.id == id && $0.sharing != nil }
        }
        if !hasSelectedInitialPeriod || !selectionExists {
            selection = .initial(subscription: subscription, periods: periods)
            hasSelectedInitialPeriod = true
        }
    }

    func beginEditing(period: SubscriptionPeriodDTO, expectedRevision: Int64) {
        guard editorSession == nil, !isSaving else { return }
        do {
            editorSession = SubscriptionSharingPeriodEditorSession(
                draft: try SubscriptionSharingPeriodDraft(period: period, expectedRevision: expectedRevision)
            )
        } catch {
            self.error = PresentedError(error, title: "无法编辑本期拼车")
        }
    }

    func beginAdding(subscription: SubscriptionDTO, periods: [SubscriptionPeriodDTO]) {
        guard editorSession == nil, !isSaving else { return }
        do {
            editorSession = SubscriptionSharingPeriodEditorSession(
                draft: try SubscriptionSharingPeriodDraft(
                    addingTo: subscription,
                    after: periods.last(where: { $0.subscriptionID == subscription.id && $0.sharing != nil })
                )
            )
        } catch {
            self.error = PresentedError(error, title: "无法添加拼车周期")
        }
    }

    func cancelEditing() {
        guard !isSaving else { return }
        editorSession = nil
        error = nil
        isPresentingOverlapConfirmation = false
    }

    func save(
        periods: [SubscriptionPeriodDTO],
        confirmingOverlap: Bool = false,
        addPeriod: @MainActor (SubscriptionPeriodAddInput) async throws -> Void,
        updatePeriod: @MainActor (SubscriptionPeriodUpdateInput) async throws -> Void,
        onSaved: @MainActor () async -> Void = {}
    ) async -> Bool {
        guard let draft = editorSession?.draft, !isSaving else { return false }
        do {
            // Validate the complete draft before requesting overlap confirmation or writing anything.
            let addition = draft.isCreating ? try draft.addInput() : nil
            let update = draft.isCreating ? nil : try draft.updateInput()
            if !confirmingOverlap, !draft.overlappingPeriods(in: periods).isEmpty {
                isPresentingOverlapConfirmation = true
                return false
            }
            isSaving = true
            defer { isSaving = false }
            if let addition { try await addPeriod(addition) }
            if let update { try await updatePeriod(update) }
            await onSaved()
            editorSession = nil
            selection = .period(draft.id)
            hasSelectedInitialPeriod = true
            error = nil
            isPresentingOverlapConfirmation = false
            return true
        } catch {
            self.error = PresentedError(error, title: "无法保存本期拼车")
            return false
        }
    }
}
