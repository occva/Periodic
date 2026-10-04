import Foundation

enum SubscriptionSharingRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case organizer
    case participant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .organizer: AppLocalization.string("车主")
        case .participant: AppLocalization.string("参与者")
        }
    }
}

/// Other members only. The subscription's own price is the sole source for "me".
struct SubscriptionSharingMember: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let money: Money?
}

struct SubscriptionSharingPlan: Hashable, Codable, Sendable {
    let role: SubscriptionSharingRole
    let purchaseMoney: Money?
    let members: [SubscriptionSharingMember]

    var memberCount: Int { members.count + 1 }

    var summary: String {
        String(format: AppLocalization.string("拼车 · %d 人 · %@"), memberCount, role.title)
    }

    func validate(myMoney: Money) throws {
        guard !members.isEmpty else { throw SubscriptionSharingError.tooFewMembers }
        guard Set(members.map(\.id)).count == members.count else {
            throw SubscriptionSharingError.duplicateMember
        }
        if role == .organizer, purchaseMoney == nil {
            throw SubscriptionSharingError.missingPurchasePrice
        }
        for member in members {
            guard !member.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SubscriptionSharingError.emptyMemberName
            }
        }
        let prices = [myMoney] + members.compactMap(\.money) + [purchaseMoney].compactMap { $0 }
        guard prices.allSatisfy({ $0.currency == myMoney.currency }) else {
            throw SubscriptionSharingError.currencyMismatch
        }
        guard prices.allSatisfy({ $0.minorUnits >= 0 }) else {
            throw Money.ValidationError.negative
        }
        _ = try quotedTotal(myMoney: myMoney)
    }

    /// An unknown quote is not a free seat. Partial totals are never presented as complete.
    func quotedTotal(myMoney: Money) throws -> Money? {
        var total = myMoney.minorUnits
        for member in members {
            guard let money = member.money else { continue }
            guard money.currency == myMoney.currency else {
                throw SubscriptionSharingError.currencyMismatch
            }
            let result = total.addingReportingOverflow(money.minorUnits)
            guard !result.overflow else { throw Money.ValidationError.overflow }
            total = result.partialValue
        }
        guard members.allSatisfy({ $0.money != nil }) else { return nil }
        return Money(minorUnits: total, currency: myMoney.currency)
    }

    func defaultPaymentMoney(myMoney: Money) -> Money {
        role == .organizer ? purchaseMoney ?? myMoney : myMoney
    }

    func copyingMembers() -> Self {
        Self(
            role: role,
            purchaseMoney: purchaseMoney,
            members: members.map { .init(id: UUID(), name: $0.name, money: $0.money) }
        )
    }

    func prorated(from sourceMonths: Int, to targetMonths: Int) throws -> Self {
        func price(_ money: Money?) throws -> Money? {
            guard let money else { return nil }
            guard let result = money.prorated(from: sourceMonths, to: targetMonths) else {
                throw Money.ValidationError.overflow
            }
            return result
        }
        return try Self(
            role: role,
            purchaseMoney: price(purchaseMoney),
            members: members.map { .init(id: $0.id, name: $0.name, money: try price($0.money)) }
        )
    }
}

enum SubscriptionSharingError: LocalizedError {
    case tooFewMembers
    case duplicateMember
    case missingPurchasePrice
    case emptyMemberName
    case currencyMismatch
    case invalidStoredPlan

    var errorDescription: String? {
        switch self {
        case .tooFewMembers: AppLocalization.string("拼车至少需要两人，人数包含自己。")
        case .duplicateMember: AppLocalization.string("拼车成员标识重复，请重新添加成员。")
        case .missingPurchasePrice: AppLocalization.string("请填写订阅总价。")
        case .emptyMemberName: AppLocalization.string("请填写拼车成员昵称。")
        case .currencyMismatch: AppLocalization.string("拼车价格必须使用同一币种，请检查成员价格和订阅总价。")
        case .invalidStoredPlan: AppLocalization.string("拼车数据无法读取，原数据已保留，请从有效备份恢复或重试。")
        }
    }
}
