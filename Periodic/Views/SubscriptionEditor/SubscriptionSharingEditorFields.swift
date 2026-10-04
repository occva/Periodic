import SwiftUI

struct SubscriptionSharingEditorFields: View {
    @Binding var draft: SubscriptionSharingDraft
    @Binding var myAmountText: String
    @Binding var currency: CurrencyCode
    let availableCurrencies: [CurrencyCode]

    @FocusState private var focusedMemberID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            configurationRow

            switch draft.role {
            case .organizer:
                HStack(spacing: 24) {
                    priceField("订阅总价", text: $draft.purchaseAmountText, identifier: "subscription-sharing-purchase")
                    priceField("我的价格", text: $myAmountText, identifier: "subscription-amount")
                }
                Divider()
                memberPrices
            case .participant:
                HStack(spacing: 24) {
                    headcountField
                    priceField("我的价格", text: $myAmountText, identifier: "subscription-amount")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var configurationRow: some View {
        HStack(spacing: 8) {
            Text("我的身份")
            Picker("我的身份", selection: $draft.role) {
                ForEach(SubscriptionSharingRole.allCases) { role in
                    Text(role.title).tag(role)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("subscription-sharing-role")

            Spacer(minLength: 16)

            Text("币种")
                .foregroundStyle(.secondary)
            Picker("币种", selection: $currency) {
                ForEach(availableCurrencies) { currency in
                    Text(currency.rawValue).tag(currency)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 80)
            .accessibilityIdentifier("subscription-currency")
        }
    }

    private func priceField(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .fixedSize()
            Spacer(minLength: 0)
            TextField(title, text: text, prompt: Text(Money(minorUnits: 0, currency: currency).inputText))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 112)
                .accessibilityHint(currency.rawValue)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity)
    }

    private var headcountField: some View {
        HStack(spacing: 8) {
            Text("拼车人数")
                .fixedSize()
            Spacer(minLength: 0)
            Text(memberCountDescription)
                .monospacedDigit()
                .lineLimit(1)
            Stepper("拼车人数", value: memberCount, in: 2...Int.max)
                .labelsHidden()
                .frame(width: 20)
                .accessibilityValue(memberCountDescription)
                .accessibilityIdentifier("subscription-sharing-count")
        }
        .frame(maxWidth: .infinity)
    }

    private var memberPrices: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("成员价格")
                    .fontWeight(.medium)
                Text(memberCountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("subscription-sharing-count")
                Spacer()
                Button(action: addMember) {
                    Label("添加成员", systemImage: "plus")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 10)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach($draft.members) { $member in
                    SubscriptionSharingMemberEditor(
                        id: member.id,
                        name: $member.name,
                        amountText: $member.amountText,
                        currency: currency,
                        nameFocus: $focusedMemberID,
                        onRemove: removalAction(for: member.id)
                    )
                }
            }
        }
    }

    private var memberCount: Binding<Int> {
        Binding(
            get: { draft.memberCount },
            set: { draft.setMemberCount($0) }
        )
    }

    private var memberCountDescription: String {
        String(format: AppLocalization.string("%d 人（含我）"), draft.memberCount)
    }

    private func addMember() {
        focusedMemberID = draft.addMember()
    }

    private func removalAction(for id: UUID) -> (@MainActor () -> Void)? {
        guard draft.members.count > 1 else { return nil }
        return { @MainActor in removeMember(id: id) }
    }

    private func removeMember(id: UUID) {
        if focusedMemberID == id { focusedMemberID = nil }
        draft.removeMember(id: id)
    }
}
