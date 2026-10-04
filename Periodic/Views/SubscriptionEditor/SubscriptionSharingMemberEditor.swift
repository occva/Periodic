import SwiftUI

struct SubscriptionSharingMemberEditor: View {
    let id: UUID
    @Binding var name: String
    @Binding var amountText: String
    let currency: CurrencyCode
    let nameFocus: FocusState<UUID?>.Binding
    let onRemove: (@MainActor () -> Void)?

    @FocusState private var isAmountFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("成员昵称", text: $name, prompt: Text("成员昵称"))
                .labelsHidden()
                .frame(minWidth: 52, maxWidth: .infinity)
                .accessibilityLabel("成员昵称")
                .focused(nameFocus, equals: id)

            Divider()
                .frame(height: 14)

            TextField("价格", text: $amountText, prompt: Text(Money(minorUnits: 0, currency: currency).inputText))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 72)
                .focused($isAmountFocused)
                .accessibilityLabel(String(
                    format: AppLocalization.string("%@ 的价格"),
                    name
                ))
                .accessibilityHint(currency.rawValue)
                .accessibilityIdentifier("subscription-sharing-member-amount")

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .frame(width: 16, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(removalLabel)
                .help(removalLabel)
            }
        }
        .textFieldStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isFocused ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: isFocused ? 2 : 1
                )
                .allowsHitTesting(false)
        }
    }

    private var isFocused: Bool {
        nameFocus.wrappedValue == id || isAmountFocused
    }

    private var removalLabel: String {
        String(format: AppLocalization.string("移除成员 %@"), name)
    }
}
