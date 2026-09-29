import SwiftUI
import UniformTypeIdentifiers

struct SubscriptionPaymentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""

    let periods: [SubscriptionPeriodDTO]
    let save: @MainActor (SubscriptionPaymentDraft) async throws -> Void

    private let initialDraft: SubscriptionPaymentDraft
    @State private var draft: SubscriptionPaymentDraft
    @State private var isSaving = false
    @State private var isImportingAttachment = false
    @State private var isPresentingFileImporter = false
    @State private var stagedAttachmentWrites: [PaymentAttachmentStore.ImportedImageWrite] = []
    @State private var didSave = false
    @State private var isPresentingDiscardConfirmation = false
    @State private var error: PresentedError?

    init(
        draft: SubscriptionPaymentDraft,
        periods: [SubscriptionPeriodDTO],
        save: @escaping @MainActor (SubscriptionPaymentDraft) async throws -> Void
    ) {
        initialDraft = draft
        _draft = State(initialValue: draft)
        self.periods = periods
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(draft.isCreating ? "记录消费" : "编辑消费")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                DatePicker(
                    "付款日期",
                    selection: $draft.paymentDate,
                    in: ...Date(),
                    displayedComponents: .date
                )

                LabeledContent("实际支付") {
                    HStack(spacing: 8) {
                        TextField(text: $draft.amountText, prompt: nil) {
                            Text("金额")
                        }
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 110)

                        Picker("币种", selection: $draft.currency) {
                            ForEach(CurrencyPreferences.availableCurrencies(
                                from: selectedCurrenciesRaw,
                                including: draft.currency
                            )) { currency in
                                Text(currency.rawValue).tag(currency)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }
                }

                Picker("关联周期", selection: $draft.periodRecordID) {
                    Text("不关联周期").tag(nil as UUID?)
                    ForEach(periods) { period in
                        Text(period.paymentPickerTitle).tag(period.id as UUID?)
                    }
                }
                .pickerStyle(.menu)

                TextField("备注", text: $draft.note, axis: .vertical)
                    .lineLimit(3...6)

                LabeledContent("消费截图") {
                    attachmentEditor
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") { requestDismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                    .disabled(isSaving || isImportingAttachment)
                Button(draft.isCreating ? "发布" : "保存") { persist() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(isSaving || isImportingAttachment)
            }
            .padding(16)
        }
        .frame(width: 520)
        .presentationSizing(.fitted)
        .fileImporter(
            isPresented: $isPresentingFileImporter,
            allowedContentTypes: [.png, .jpeg],
            allowsMultipleSelection: true,
            onCompletion: handleAttachmentSelection
        )
        .interactiveDismissDisabled(
            isSaving || isImportingAttachment || draft != initialDraft
        )
        .confirmationDialog(
            "放弃未保存的修改？",
            isPresented: $isPresentingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("消费记录和新选择的截图都不会保存。")
        }
        .onDisappear {
            guard !didSave, !isSaving, !stagedAttachmentWrites.isEmpty else { return }
            Task {
                await services.discardUncommittedPaymentAttachments(stagedAttachmentWrites)
            }
        }
        .errorAlert($error)
    }

    @ViewBuilder
    private var attachmentEditor: some View {
        if draft.attachmentReferences.isEmpty {
            Button("选择截图…") { isPresentingFileImporter = true }
                .disabled(isSaving || isImportingAttachment)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(draft.attachmentReferences, id: \.self) { reference in
                            PaymentAttachmentImageView(
                                reference: reference,
                                maximumSize: CGSize(width: 140, height: 96)
                            )
                                .background(
                                    .quaternary,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Button(role: .destructive) {
                                        removeAttachment(reference)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2.weight(.bold))
                                            .frame(width: 20, height: 20)
                                            .background(.regularMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                    .help("移除截图")
                                    .accessibilityLabel("移除截图")
                                    .disabled(isSaving || isImportingAttachment)
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("消费截图")
                        }
                    }
                }

                Button("添加截图…") { isPresentingFileImporter = true }
                    .buttonStyle(.link)
                    .disabled(isSaving || isImportingAttachment)
            }
        }
    }

    private func persist() {
        isSaving = true
        Task { @MainActor in
            do {
                try await save(draft)
                didSave = true
                let retainedReferences = Set(draft.attachmentReferences)
                await services.finalizeCommittedPaymentAttachments(
                    stagedAttachmentWrites,
                    retainedReferences: retainedReferences
                )
                isSaving = false
                dismiss()
            } catch {
                self.error = PresentedError(error, title: "无法保存消费记录")
                isSaving = false
            }
        }
    }

    private func requestDismiss() {
        if draft == initialDraft {
            dismiss()
        } else {
            isPresentingDiscardConfirmation = true
        }
    }

    private func handleAttachmentSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            importAttachments(from: urls)
        case .failure(let selectionError):
            error = PresentedError(selectionError, title: "无法选择消费截图")
        }
    }

    private func importAttachments(from urls: [URL]) {
        isImportingAttachment = true
        Task { @MainActor in
            defer { isImportingAttachment = false }
            let existingReferences = Set(draft.attachmentReferences)
            var selectionWrites: [PaymentAttachmentStore.ImportedImageWrite] = []
            do {
                for url in urls {
                    selectionWrites.append(
                        try await services.paymentAttachmentStore.persistLocalImage(from: url)
                    )
                }
                let selectedReferences = selectionWrites.map(\.reference)
                draft.attachmentReferences = PaymentAttachmentReference.removingDuplicates(
                    draft.attachmentReferences + selectedReferences
                )
                stagedAttachmentWrites.append(contentsOf: selectionWrites)
            } catch {
                await services.discardUncommittedPaymentAttachments(
                    selectionWrites,
                    keeping: existingReferences
                )
                self.error = PresentedError(error, title: "无法使用所选截图")
            }
        }
    }

    private func removeAttachment(_ reference: String) {
        draft.attachmentReferences.removeAll { $0 == reference }
    }
}
