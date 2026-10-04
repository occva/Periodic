import Foundation

struct SubscriptionPaymentDraft: Identifiable, Equatable {
    let id: UUID
    let original: SubscriptionPaymentDTO?
    var paymentDate: Date
    var amountText: String
    var currency: CurrencyCode
    var periodRecordID: UUID?
    var periodStart: LocalDate?
    var periodEnd: LocalDate?
    var note: String
    var attachmentReferences: [String]

    var isCreating: Bool { original == nil }

    init(subscription: SubscriptionDTO) {
        id = UUID()
        original = nil
        paymentDate = Date()
        amountText = (subscription.sharing?.defaultPaymentMoney(myMoney: subscription.money) ?? subscription.money).inputText
        currency = subscription.money.currency
        periodRecordID = nil
        periodStart = nil
        periodEnd = nil
        note = ""
        attachmentReferences = []
    }

    init(payment: SubscriptionPaymentDTO) {
        id = payment.id
        original = payment
        paymentDate = payment.paymentDate.date()
        amountText = payment.money.inputText
        currency = payment.money.currency
        periodRecordID = payment.periodRecordID
        periodStart = payment.periodStart
        periodEnd = payment.periodEnd
        note = payment.note
        attachmentReferences = payment.attachmentReferences
    }

    func addInput(
        subscriptionID: UUID,
        expectedSubscriptionRevision: Int64,
        periods: [SubscriptionPeriodDTO]
    ) throws -> SubscriptionPaymentAddInput {
        guard isCreating else { throw SubscriptionPaymentEditError.invalidDraft }
        let values = try validatedValues(periods: periods)
        return SubscriptionPaymentAddInput(
            payment: SubscriptionPaymentCreateInput(
                id: id,
                subscriptionID: subscriptionID,
                periodRecordID: periodRecordID,
                kind: .manual,
                paymentDate: values.paymentDate,
                money: values.money,
                periodStart: values.periodStart,
                periodEnd: values.periodEnd,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                attachmentReferences: attachmentReferences
            ),
            expectedSubscriptionRevision: expectedSubscriptionRevision
        )
    }

    func updateInput(
        expectedSubscriptionRevision: Int64,
        periods: [SubscriptionPeriodDTO]
    ) throws -> SubscriptionPaymentUpdateInput {
        guard let original else { throw SubscriptionPaymentEditError.invalidDraft }
        let values = try validatedValues(periods: periods)
        return SubscriptionPaymentUpdateInput(
            original: original,
            expectedSubscriptionRevision: expectedSubscriptionRevision,
            periodRecordID: periodRecordID,
            paymentDate: values.paymentDate,
            money: values.money,
            periodStart: values.periodStart,
            periodEnd: values.periodEnd,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            attachmentReferences: attachmentReferences
        )
    }

    private func validatedValues(
        periods: [SubscriptionPeriodDTO]
    ) throws -> (
        paymentDate: LocalDate,
        money: Money,
        periodStart: LocalDate?,
        periodEnd: LocalDate?
    ) {
        let paymentDate = LocalDate(paymentDate)
        guard paymentDate <= .today else {
            throw SubscriptionPaymentEditError.futurePaymentDate
        }
        let money = try Money.parse(amountText, currency: currency)
        let selectedPeriod: SubscriptionPeriodDTO?
        if let periodRecordID {
            guard let matchedPeriod = periods.first(where: { $0.id == periodRecordID }) else {
                throw SubscriptionPaymentEditError.missingPeriod
            }
            selectedPeriod = matchedPeriod
        } else {
            selectedPeriod = nil
        }
        let didChangePeriodLink = periodRecordID != original?.periodRecordID
        let snapshot = if isCreating || didChangePeriodLink, let selectedPeriod {
            (selectedPeriod.start, selectedPeriod.end)
        } else {
            (periodStart, periodEnd)
        }
        return (paymentDate, money, snapshot.0, snapshot.1)
    }
}

enum SubscriptionPaymentEditError: LocalizedError {
    case futurePaymentDate
    case missingPeriod
    case invalidDraft

    var errorDescription: String? {
        switch self {
        case .futurePaymentDate: "付款日期不能晚于今天。"
        case .missingPeriod: "关联的周期记录已不存在，请重新选择。"
        case .invalidDraft: "消费记录草稿状态无效，请取消后重试。"
        }
    }
}

extension SubscriptionPeriodDTO {
    var paymentPickerTitle: String {
        let endTitle = end?.displayText ?? AppLocalization.string("永久有效")
        return "\(start.displayText) – \(endTitle)"
    }
}
