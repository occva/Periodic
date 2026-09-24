import Foundation
import SwiftData

@ModelActor
actor SubscriptionStore {
    enum StoreError: LocalizedError {
        case invalidStoredValue(String)
        case notFound
        case periodNotFound
        case incompletePeriodDates
        case revisionConflict

        var errorDescription: String? {
            switch self {
            case .invalidStoredValue(let field): "订阅数据的 \(field) 字段无法识别。"
            case .notFound: "这条订阅已不存在。"
            case .periodNotFound: "这条周期记录已不存在。"
            case .incompletePeriodDates: "开始日期和到期日期必须同时填写，才能添加周期记录。"
            case .revisionConflict: "这条订阅已在别处修改，请刷新后重试。"
            }
        }
    }

    func fetchAll() throws -> [SubscriptionDTO] {
        let descriptor = FetchDescriptor<SubscriptionRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let records = try modelContext.fetch(descriptor)
        var subscriptions: [SubscriptionDTO] = []
        var firstConversionError: (any Error)?
        for record in records {
            do {
                subscriptions.append(try makeDTO(record))
            } catch {
                firstConversionError = firstConversionError ?? error
            }
        }
        if subscriptions.isEmpty, !records.isEmpty, let firstConversionError {
            throw firstConversionError
        }
        if firstConversionError != nil {
            AppLog.persistence.warning("Skipped invalid subscription records while loading")
        }
        return subscriptions
    }

    func create(_ input: SubscriptionCreateInput) throws -> UUID {
        do {
            modelContext.insert(SubscriptionRecord(input: input))
            if let period = initialPeriod(for: input) {
                modelContext.insert(SubscriptionPeriodRecord(input: period))
            }
            try modelContext.save()
            return input.id
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func create(
        _ inputs: [SubscriptionCreateInput],
        additionalPeriods: [SubscriptionPeriodCreateInput] = []
    ) throws {
        do {
            for input in inputs {
                modelContext.insert(SubscriptionRecord(input: input))
                if let period = initialPeriod(for: input) {
                    modelContext.insert(SubscriptionPeriodRecord(input: period))
                }
            }
            for period in additionalPeriods {
                modelContext.insert(SubscriptionPeriodRecord(input: period))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func fetchPeriods(for subscriptionID: UUID) throws -> [SubscriptionPeriodDTO] {
        let descriptor = FetchDescriptor<SubscriptionPeriodRecord>(
            predicate: #Predicate { $0.subscriptionID == subscriptionID },
            sortBy: [
                SortDescriptor(\.startDay, order: .forward),
                SortDescriptor(\.createdAt, order: .forward),
            ]
        )
        let records = try modelContext.fetch(descriptor)
        var periods: [SubscriptionPeriodDTO] = []
        var firstConversionError: (any Error)?
        for record in records {
            do {
                periods.append(try makePeriodDTO(record))
            } catch {
                firstConversionError = firstConversionError ?? error
            }
        }
        if periods.isEmpty, !records.isEmpty, let firstConversionError {
            throw firstConversionError
        }
        if firstConversionError != nil {
            AppLog.persistence.warning("Skipped invalid subscription period records while loading")
        }
        return periods
    }

    func update(
        _ input: SubscriptionCreateInput,
        expectedRevision: Int64,
        historyPolicy: SubscriptionUpdateHistoryPolicy
    ) throws {
        do {
            let descriptor = FetchDescriptor<SubscriptionRecord>()
            guard let record = try modelContext.fetch(descriptor).first(where: { $0.id == input.id }) else {
                throw StoreError.notFound
            }
            guard record.revision == expectedRevision else {
                throw StoreError.revisionConflict
            }
            switch historyPolicy {
            case .currentOnly:
                if input.billingKind == .lifetime {
                    try insertLifetimePeriodIfNeeded(
                        for: input,
                        fallbackStart: LocalDate(record.createdAt)
                    )
                }
            case .appendPeriodRecord:
                guard let period = initialPeriod(for: input, source: .manual) else {
                    throw StoreError.incompletePeriodDates
                }
                modelContext.insert(SubscriptionPeriodRecord(input: period))
            }
            record.apply(input)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func addPeriod(_ input: SubscriptionPeriodAddInput) throws {
        do {
            let descriptor = FetchDescriptor<SubscriptionRecord>()
            guard let subscription = try modelContext.fetch(descriptor).first(where: {
                $0.id == input.period.subscriptionID
            }) else {
                throw StoreError.notFound
            }
            guard subscription.revision == input.expectedSubscriptionRevision else {
                throw StoreError.revisionConflict
            }

            modelContext.insert(SubscriptionPeriodRecord(input: input.period))
            subscription.markHistoryChanged()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func updatePeriod(_ input: SubscriptionPeriodUpdateInput) throws {
        do {
            let subscriptionDescriptor = FetchDescriptor<SubscriptionRecord>()
            guard let subscription = try modelContext.fetch(subscriptionDescriptor).first(where: {
                $0.id == input.original.subscriptionID
            }) else {
                throw StoreError.notFound
            }
            guard subscription.revision == input.expectedSubscriptionRevision else {
                throw StoreError.revisionConflict
            }

            let periodDescriptor = FetchDescriptor<SubscriptionPeriodRecord>()
            guard let period = try modelContext.fetch(periodDescriptor).first(where: {
                $0.id == input.original.id && $0.subscriptionID == input.original.subscriptionID
            }) else {
                throw StoreError.periodNotFound
            }
            guard try makePeriodDTO(period) == input.original else {
                throw StoreError.revisionConflict
            }

            period.apply(input)
            subscription.markHistoryChanged()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func deletePeriod(_ input: SubscriptionPeriodDeleteInput) throws {
        do {
            let subscriptionID = input.original.subscriptionID
            var subscriptionDescriptor = FetchDescriptor<SubscriptionRecord>(
                predicate: #Predicate { $0.id == subscriptionID }
            )
            subscriptionDescriptor.fetchLimit = 1
            guard let subscription = try modelContext.fetch(subscriptionDescriptor).first else {
                throw StoreError.notFound
            }
            guard subscription.revision == input.expectedSubscriptionRevision else {
                throw StoreError.revisionConflict
            }

            let periodID = input.original.id
            var periodDescriptor = FetchDescriptor<SubscriptionPeriodRecord>(
                predicate: #Predicate {
                    $0.id == periodID && $0.subscriptionID == subscriptionID
                }
            )
            periodDescriptor.fetchLimit = 1
            guard let period = try modelContext.fetch(periodDescriptor).first else {
                throw StoreError.periodNotFound
            }
            guard try makePeriodDTO(period) == input.original else {
                throw StoreError.revisionConflict
            }

            modelContext.delete(period)
            subscription.markHistoryChanged()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func confirmAutomaticRenewal(
        _ request: SubscriptionRenewalRequest,
        referenceDate: LocalDate = .today
    ) throws -> SubscriptionRenewalPreview {
        do {
            let subscriptionID = request.subscriptionID
            var descriptor = FetchDescriptor<SubscriptionRecord>(
                predicate: #Predicate { $0.id == subscriptionID }
            )
            descriptor.fetchLimit = 1
            guard let record = try modelContext.fetch(descriptor).first else {
                throw StoreError.notFound
            }
            guard record.revision == request.expectedRevision,
                  record.expiryDay == request.expectedExpiry.dayNumber else {
                throw StoreError.revisionConflict
            }

            let preview = try SubscriptionRenewalRule.preview(
                subscription: makeDTO(record),
                referenceDate: referenceDate
            )
            modelContext.insert(
                SubscriptionPeriodRecord(
                    input: SubscriptionPeriodCreateInput(
                        id: UUID(),
                        subscriptionID: record.id,
                        billingKind: .recurring,
                        cycleMonths: preview.cycleMonths,
                        start: preview.nextStart,
                        end: preview.nextExpiry,
                        money: preview.money,
                        source: .renewal
                    )
                )
            )
            record.applyRenewal(start: preview.nextStart, expiry: preview.nextExpiry)
            try modelContext.save()
            return preview
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Completes the lifetime-history invariant for data created before the
    /// app began materializing a bounded lifetime period automatically.
    func backfillLifetimePeriods() throws -> Int {
        do {
            let subscriptions = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
            let periods = try modelContext.fetch(FetchDescriptor<SubscriptionPeriodRecord>())
            let lifetimePeriods = periods.filter {
                $0.billingKindRaw == BillingKind.lifetime.rawValue
            }
            var subscriptionIDsWithLifetimePeriod = Set(lifetimePeriods.map(\.subscriptionID))
            var changedCount = 0

            for period in lifetimePeriods where period.endDay == nil {
                period.endDay = LocalDate.defaultLifetimeHistoryEnd.dayNumber
                changedCount += 1
            }

            for subscription in subscriptions where
                subscription.billingKindRaw == BillingKind.lifetime.rawValue
                    && !subscriptionIDsWithLifetimePeriod.contains(subscription.id) {
                guard let currency = CurrencyCode(rawValue: subscription.currencyCode),
                      currency.scale == subscription.currencyScale else {
                    AppLog.persistence.warning(
                        "Skipped lifetime history backfill for a subscription with invalid currency metadata"
                    )
                    continue
                }
                let period = SubscriptionPeriodCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    billingKind: .lifetime,
                    cycleMonths: nil,
                    start: subscription.periodStartDay.map(LocalDate.init(dayNumber:))
                        ?? LocalDate(subscription.createdAt),
                    end: .defaultLifetimeHistoryEnd,
                    money: Money(
                        minorUnits: subscription.periodAmountMinor,
                        currency: currency
                    ),
                    source: .initial
                )
                modelContext.insert(SubscriptionPeriodRecord(input: period))
                subscriptionIDsWithLifetimePeriod.insert(subscription.id)
                changedCount += 1
            }

            if changedCount > 0 {
                try modelContext.save()
            }
            return changedCount
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func makeDTO(_ record: SubscriptionRecord) throws -> SubscriptionDTO {
        guard let category = ServiceCategory(rawValue: record.categoryRaw) else {
            throw StoreError.invalidStoredValue("categoryRaw")
        }
        guard let managementState = ManagementState(rawValue: record.managementStateRaw) else {
            throw StoreError.invalidStoredValue("managementStateRaw")
        }
        guard let billingKind = BillingKind(rawValue: record.billingKindRaw) else {
            throw StoreError.invalidStoredValue("billingKindRaw")
        }
        guard let currency = CurrencyCode(rawValue: record.currencyCode),
              currency.scale == record.currencyScale else {
            throw StoreError.invalidStoredValue("currencyCode")
        }

        return SubscriptionDTO(
            id: record.id,
            name: record.name,
            symbolName: record.symbolName,
            iconResourceName: record.iconResourceName,
            iconURLString: record.iconURLString,
            category: category,
            managementState: managementState,
            billingKind: billingKind,
            periodStart: record.periodStartDay.map(LocalDate.init(dayNumber:)),
            expiry: record.expiryDay.map(LocalDate.init(dayNumber:)),
            cycleMonths: record.cycleMonths,
            money: Money(minorUnits: record.periodAmountMinor, currency: currency),
            note: record.note,
            reminderEnabled: record.reminderEnabled,
            automaticallyRenews: record.automaticallyRenews,
            revision: record.revision,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private func makePeriodDTO(_ record: SubscriptionPeriodRecord) throws -> SubscriptionPeriodDTO {
        guard let billingKind = BillingKind(rawValue: record.billingKindRaw) else {
            throw StoreError.invalidStoredValue("period.billingKindRaw")
        }
        guard let currency = CurrencyCode(rawValue: record.currencyCode),
              currency.scale == record.currencyScale else {
            throw StoreError.invalidStoredValue("period.currencyCode")
        }
        guard let source = SubscriptionPeriodSource(rawValue: record.sourceRaw) else {
            throw StoreError.invalidStoredValue("period.sourceRaw")
        }
        return SubscriptionPeriodDTO(
            id: record.id,
            subscriptionID: record.subscriptionID,
            billingKind: billingKind,
            cycleMonths: record.cycleMonths,
            start: LocalDate(dayNumber: record.startDay),
            end: record.endDay.map(LocalDate.init(dayNumber:)),
            money: Money(minorUnits: record.amountMinor, currency: currency),
            source: source,
            createdAt: record.createdAt
        )
    }

    private func initialPeriod(
        for input: SubscriptionCreateInput,
        fallbackStart: LocalDate = .today,
        source: SubscriptionPeriodSource = .initial
    ) -> SubscriptionPeriodCreateInput? {
        switch input.billingKind {
        case .recurring:
            guard let start = input.periodStart, let expiry = input.expiry else { return nil }
            return SubscriptionPeriodCreateInput(
                id: UUID(),
                subscriptionID: input.id,
                billingKind: .recurring,
                cycleMonths: input.cycleMonths,
                start: start,
                end: expiry,
                money: input.money,
                source: source
            )
        case .lifetime:
            return SubscriptionPeriodCreateInput(
                id: UUID(),
                subscriptionID: input.id,
                billingKind: .lifetime,
                cycleMonths: nil,
                start: input.periodStart ?? fallbackStart,
                end: .defaultLifetimeHistoryEnd,
                money: input.money,
                source: source
            )
        }
    }

    private func insertLifetimePeriodIfNeeded(
        for input: SubscriptionCreateInput,
        fallbackStart: LocalDate
    ) throws {
        let subscriptionID = input.id
        let lifetimeRawValue = BillingKind.lifetime.rawValue
        var descriptor = FetchDescriptor<SubscriptionPeriodRecord>(
            predicate: #Predicate {
                $0.subscriptionID == subscriptionID
                    && $0.billingKindRaw == lifetimeRawValue
            }
        )
        descriptor.fetchLimit = 1
        guard try modelContext.fetch(descriptor).isEmpty else {
            return
        }
        guard let period = initialPeriod(
            for: input,
            fallbackStart: fallbackStart,
            source: .manual
        ) else { return }
        modelContext.insert(SubscriptionPeriodRecord(input: period))
    }
}
