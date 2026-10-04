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
    @State private var paymentDate = Date()
    @State private var note = ""
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
        _amountText = State(initialValue: preview.defaultPaymentMoney.inputText)
        _currency = State(initialValue: preview.defaultPaymentMoney.currency)
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

                LabeledContent("本期价格") {
                    Text(quotedMoney.displayText(style: currencyDisplayStyle))
                        .monospacedDigit()
                }

                if let plan = preview.sharing {
                    Text(plan.summary)
                    Text(AppLocalization.string(plan.role == .organizer
                        ? "个人价格与订阅总价分别记录；实际支付不会自动更改当前拼车价格。"
                        : "实际支付不会自动更改我的价格。"))
                        .foregroundStyle(.secondary)
                }

                DatePicker(
                    "付款日期",
                    selection: $paymentDate,
                    in: ...Date(),
                    displayedComponents: .date
                )

                LabeledContent("实际支付") {
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

                TextField("备注", text: $note, axis: .vertical)
                    .lineLimit(2...4)

                LabeledContent("新周期") {
                    Text(periodDescription)
                        .monospacedDigit()
                }

                LabeledContent("记录") {
                    Text("同时保存续费周期和消费动态；不会修改以后续费使用的当前报价")
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
        .errorAlert($error)
        .onChange(of: cycle) { oldCycle, newCycle in
            let oldDefault = preview.defaultPaymentMoney.prorated(
                from: preview.cycleMonths, to: oldCycle.rawValue
            )
            if amountText == oldDefault?.inputText,
               currency == preview.defaultPaymentMoney.currency,
               let money = preview.defaultPaymentMoney.prorated(
                from: preview.cycleMonths, to: newCycle.rawValue
            ) {
                amountText = money.inputText
            }
        }
    }

    private var periodDescription: String {
        guard let expiry = preview.nextStart
            .addingMonths(cycle.rawValue)?
            .addingDays(-1) else {
            return AppLocalization.string("日期无法计算")
        }
        return "\(preview.nextStart.displayText) 至 \(expiry.displayText)"
    }

    private var quotedMoney: Money {
        preview.money.prorated(
            from: preview.cycleMonths,
            to: cycle.rawValue
        ) ?? preview.money
    }

    private func save() {
        do {
            let money = try Money.parse(amountText, currency: currency)
            let request = SubscriptionRenewalRequest(
                subscriptionID: preview.subscriptionID,
                expectedRevision: preview.expectedRevision,
                expectedExpiry: preview.previousExpiry,
                cycleMonths: cycle.rawValue,
                quotedMoney: quotedMoney,
                paymentDate: LocalDate(paymentDate),
                paymentMoney: money,
                paymentNote: note.trimmingCharacters(in: .whitespacesAndNewlines)
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
