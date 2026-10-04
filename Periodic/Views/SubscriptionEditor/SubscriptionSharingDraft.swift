import Foundation

struct SubscriptionSharingMemberDraft: Identifiable {
    let id: UUID
    var name: String
    var amountText: String
}

struct SubscriptionSharingDraft {
    var isEnabled: Bool
    var role: SubscriptionSharingRole
    var purchaseAmountText: String
    var members: [SubscriptionSharingMemberDraft]

    init(plan: SubscriptionSharingPlan? = nil) {
        isEnabled = plan != nil
        role = plan?.role ?? .participant
        purchaseAmountText = plan?.purchaseMoney?.inputText ?? ""
        members = plan?.members.map {
            .init(id: $0.id, name: $0.name, amountText: $0.money?.inputText ?? "")
        } ?? [.init(id: UUID(), name: AppLocalization.string("成员 2"), amountText: "")]
    }

    var memberCount: Int { members.count + 1 }

    @discardableResult
    mutating func addMember() -> UUID {
        let id = UUID()
        members.append(.init(
            id: id,
            name: String(format: AppLocalization.string("成员 %d"), memberCount + 1),
            amountText: ""
        ))
        return id
    }

    mutating func removeMember(id: UUID) {
        guard members.count > 1 else { return }
        members.removeAll { $0.id == id }
    }

    mutating func setMemberCount(_ count: Int) {
        let targetCount = max(2, count)
        while memberCount < targetCount { addMember() }
        if memberCount > targetCount {
            members.removeLast(memberCount - targetCount)
        }
    }

    func plan(myMoney: Money) throws -> SubscriptionSharingPlan? {
        guard isEnabled else { return nil }
        func parseOptional(_ text: String) throws -> Money? {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return try Money.parse(text, currency: myMoney.currency)
        }
        let result = try SubscriptionSharingPlan(
            role: role,
            purchaseMoney: parseOptional(purchaseAmountText),
            members: members.map {
                let name = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw SubscriptionSharingError.emptyMemberName }
                let money = try parseOptional($0.amountText)
                if role == .organizer, money == nil {
                    throw SubscriptionSharingDraftError.missingMemberPrice(name)
                }
                return .init(
                    id: $0.id,
                    name: name,
                    money: money
                )
            }
        )
        try result.validate(myMoney: myMoney)
        return result
    }
}

enum SubscriptionSharingDraftError: LocalizedError, Equatable {
    case missingMemberPrice(String)

    var errorDescription: String? {
        switch self {
        case .missingMemberPrice(let name):
            String(format: AppLocalization.string("请填写 %@ 的价格。"), name)
        }
    }
}
