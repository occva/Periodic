import SwiftUI

struct SubscriptionRenewalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""

    let preview: SubscriptionRenewalPreview
    let confirmRenewal: @MainActor (SubscriptionRenewalRequest) async throws -> Void
    let onConfirmed: @MainActor () async -> Void

    @State private var cycle: BillingCycle
    @State private var amountText: String
    @State private var currency: CurrencyCode
    @State private var isSaving = false
    @State private var error: PresentedError?

    init(
        preview: SubscriptionRenewalPreview,
        confirmRenewal: @escaping @MainActor (SubscriptionRenewalRequest) async throws -> Void,
        onConfirmed: @escaping @MainActor () async -> Void = {}
    ) {
        self.preview = preview
        self.confirmRenewal = confirmRenewal
        self.onConfirmed = onConfirmed
        _cycle = State(
            initialValue: BillingCycle(rawValue: preview.cycleMonths) ?? .monthly
        )
        _amountText = State(initialValue: preview.money.inputText)
        _currency = State(initialValue: preview.money.currency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("自定义续费")
                .font(.title2.weight(.semibold))

            Form {
                Picker("续费周期", selection: $cycle) {
                    ForEach(BillingCycle.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                LabeledContent("续费金额") {
                    HStack(spacing: 8) {
                        TextField("金额", text: $amountText)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                        Picker("币种", selection: $currency) {
                            ForEach(
                                CurrencyPreferences.availableCurrencies(
                                    from: selectedCurrenciesRaw,
                                    including: currency
                                )
                            ) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                }

                LabeledContent("新周期") {
                    Text(periodDescription)
                        .monospacedDigit()
                }

                LabeledContent("记录") {
                    Text("保存为续费周期，并同步更新当前周期与报价")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                Button("确认续费") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 500)
        .presentationSizing(.fitted)
        .onChange(of: cycle) { _, newCycle in
            guard let amount = preview.money.prorated(
                from: preview.cycleMonths,
                to: newCycle.rawValue
            ) else { return }
            amountText = amount.inputText
            currency = amount.currency
        }
        .errorAlert($error)
    }

    private var periodDescription: String {
        guard let expiry = preview.nextStart
            .addingMonths(cycle.rawValue)?
            .addingDays(-1) else {
            return AppLocalization.string("日期无法计算")
        }
        return "\(preview.nextStart.displayText) 至 \(expiry.displayText)"
    }

    private func save() {
        do {
            let money = try Money.parse(amountText, currency: currency)
            let request = SubscriptionRenewalRequest(
                subscriptionID: preview.subscriptionID,
                expectedRevision: preview.expectedRevision,
                expectedExpiry: preview.previousExpiry,
                cycleMonths: cycle.rawValue,
                money: money
            )
            isSaving = true
            Task { @MainActor in
                do {
                    try await confirmRenewal(request)
                    await onConfirmed()
                    isSaving = false
                    dismiss()
                } catch {
                    self.error = PresentedError(error, title: "无法确认续费")
                    isSaving = false
                }
            }
        } catch {
            self.error = PresentedError(error, title: "请检查续费金额")
        }
    }
}
