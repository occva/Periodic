import SwiftUI

struct SubscriptionSharingPeriodEditor: View {
    @AppStorage(PreferenceKey.selectedCurrencies) private var selectedCurrenciesRaw = ""
    @Binding var draft: SubscriptionSharingPeriodDraft

    var body: some View {
        Form {
            Section(draft.isCreating ? "添加周期" : "本期周期") {
                Picker("周期", selection: Binding(
                    get: { draft.period.kind },
                    set: { draft.selectKind($0) }
                )) {
                    ForEach(SubscriptionPeriodKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 24) {
                    DatePicker("开始日期", selection: $draft.period.startDate, displayedComponents: .date)
                    if draft.period.kind != .lifetime {
                        DatePicker("结束日期", selection: $draft.period.endDate, displayedComponents: .date)
                    }
                }
                .datePickerStyle(.field)
            }

            SubscriptionSharingEditorSection(
                draft: $draft.sharing,
                myAmountText: $draft.period.amountText,
                currency: $draft.period.currency,
                availableCurrencies: CurrencyPreferences.availableCurrencies(
                    from: selectedCurrenciesRaw,
                    including: draft.period.currency
                )
            )

            Section {
                switch pricePreview {
                case .success(let preview):
                    SubscriptionSharingPriceSummaryView(plan: preview.plan, myMoney: preview.money)
                case .failure(let error):
                    Text(error.localizedDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var pricePreview: Result<(plan: SubscriptionSharingPlan, money: Money), any Error> {
        Result { try draft.pricePreview() }
    }
}
