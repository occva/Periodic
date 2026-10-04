import SwiftUI

struct SubscriptionSharingEditorSection: View {
    @Binding var draft: SubscriptionSharingDraft
    @Binding var myAmountText: String
    @Binding var currency: CurrencyCode
    let availableCurrencies: [CurrencyCode]

    var body: some View {
        Section("拼车价格") {
            SubscriptionSharingEditorFields(
                draft: $draft,
                myAmountText: $myAmountText,
                currency: $currency,
                availableCurrencies: availableCurrencies
            )
        }
    }
}
