import Foundation
import SwiftData
import Testing
@testable import Periodic

struct SubscriptionDomainTests {
    @Test func languageAndCurrencyPreferencesResolvePersistedValues() {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: PreferenceKey.language)
        let previousCurrency = defaults.string(forKey: PreferenceKey.defaultCurrency)
        let previousUsesCurrencySymbols = defaults.object(
            forKey: PreferenceKey.usesCurrencySymbols
        ) as? Bool
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: PreferenceKey.language)
            } else {
                defaults.removeObject(forKey: PreferenceKey.language)
            }
            if let previousCurrency {
                defaults.set(previousCurrency, forKey: PreferenceKey.defaultCurrency)
            } else {
                defaults.removeObject(forKey: PreferenceKey.defaultCurrency)
            }
            if let previousUsesCurrencySymbols {
                defaults.set(
                    previousUsesCurrencySymbols,
                    forKey: PreferenceKey.usesCurrencySymbols
                )
            } else {
                defaults.removeObject(forKey: PreferenceKey.usesCurrencySymbols)
            }
        }

        defaults.set(AppLanguage.english.rawValue, forKey: PreferenceKey.language)
        defaults.set(CurrencyCode.usd.rawValue, forKey: PreferenceKey.defaultCurrency)
        defaults.set(true, forKey: PreferenceKey.usesCurrencySymbols)

        #expect(AppDestination.dashboard.title == "Home")
        #expect(TimelineRange.sixMonths.title == "6 Months")
        #expect(TimelineRange.threeYears.title == "3 Years")
        #expect(AppPreferenceValues.defaultCurrency == .usd)
        #expect(AppPreferenceValues.currencyDisplayStyle == .symbol)
    }

    @Test func mainSidebarOrderAndTitlesMatchProductNavigation() {
        #expect(AppDestination.allCases == [.dashboard, .timeline, .overview, .templates])
        #expect(AppDestination.allCases.map(\.title) == ["首页", "时间轴视图", "表格视图", "模板管理"])
    }

    @Test func builtinCatalogContainsOnlyTemplatesWithBundledIcons() throws {
        let catalog = try BuiltinTemplateCatalog.load()

        #expect(catalog.version == "2.3.0")
        #expect(catalog.templates.count == 125)
        #expect(catalog.templates.allSatisfy { $0.iconResourceName != nil })
        #expect(!catalog.templates.contains { $0.key == .builtin("builtin.apple-icloud") })

        let categoriesByKey = Dictionary(
            uniqueKeysWithValues: catalog.templates.map { ($0.key, $0.category) }
        )
        #expect(categoriesByKey[.builtin("builtin.discord-nitro")] == .communication)
        #expect(categoriesByKey[.builtin("builtin.calm")] == .household)
        #expect(categoriesByKey[.builtin("builtin.tradingview")] == .tools)
        #expect(categoriesByKey[.builtin("builtin.patreon")] == .media)
        #expect(categoriesByKey[.builtin("builtin.claude")] == .tools)
        #expect(categoriesByKey[.builtin("builtin.gemini")] == .tools)
    }

    @Test func moneyRespectsCurrencyPrecision() throws {
        let cny = try Money.parse("88.50", currency: .cny)
        #expect(cny.minorUnits == 8_850)
        #expect(cny.displayText == "CNY 88.50")
        #expect(cny.displayText(style: .symbol) == "¥88.50（人民币）")

        let jpy = try Money.parse("88", currency: .jpy)
        #expect(jpy.minorUnits == 88)
        #expect(jpy.displayText(style: .symbol) == "¥88（日元）")
        #expect(throws: Money.ValidationError.self) {
            try Money.parse("88.5", currency: .jpy)
        }

        let annual = try Money.parse("120", currency: .cny)
        #expect(annual.monthlyAmount(cycleMonths: 12) == 10)
        #expect(annual.annualAmount(cycleMonths: 12) == 120)
        #expect(
            annual.monthlyEstimate(cycleMonths: 12, style: .symbol)
                == "¥10.00（人民币）"
        )
    }

    @Test func localDateUsesCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let localDate = LocalDate(date, calendar: calendar)

        #expect(localDate.displayText == "2026/10/15")
    }

    @Test func localDateKeepsGregorianDateWhenSystemCalendarIsNonGregorian() throws {
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let date = try #require(
            sourceCalendar.date(from: DateComponents(year: 2026, month: 9, day: 23))
        )
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = sourceCalendar.timeZone

        let localDate = LocalDate(date, calendar: buddhistCalendar)
        let restoredDate = localDate.date(calendar: buddhistCalendar)
        let restoredComponents = sourceCalendar.dateComponents(
            [.year, .month, .day],
            from: restoredDate
        )

        #expect(localDate.displayText == "2026/09/23")
        #expect(restoredComponents.year == 2026)
        #expect(restoredComponents.month == 9)
        #expect(restoredComponents.day == 23)
    }

    @Test func localDateMonthArithmeticClampsAtMonthEnd() throws {
        let january31 = LocalDate(
            try #require(
                Calendar(identifier: .gregorian).date(
                    from: DateComponents(year: 2028, month: 1, day: 31)
                )
            )
        )

        #expect(january31.addingMonths(1)?.displayText == "2028/02/29")
        #expect(january31.addingMonths(13)?.displayText == "2029/02/28")
    }

    @Test func automaticRenewalBecomesConfirmableOnExpiryDay() throws {
        let expiry = LocalDate.today
        let subscription = makeRenewingSubscription(expiry: expiry)

        #expect(throws: SubscriptionRenewalRule.RuleError.self) {
            try SubscriptionRenewalRule.preview(
                subscription: subscription,
                referenceDate: try #require(expiry.addingDays(-1))
            )
        }

        let preview = try SubscriptionRenewalRule.preview(
            subscription: subscription,
            referenceDate: expiry
        )
        #expect(preview.nextStart == expiry.addingDays(1))
        #expect(preview.nextExpiry == preview.nextStart.addingMonths(1)?.addingDays(-1))
    }

    @Test func renewalNotificationPlansFutureExpiryAtNineAM() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let referenceDate = LocalDate(
            try #require(
                calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))
            ),
            calendar: calendar
        )
        let expiry = try #require(referenceDate.addingDays(1))
        let now = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 24, hour: 12)
            )
        )

        let plans = RenewalNotificationPlan.plans(
            subscriptions: [makeRenewingSubscription(expiry: expiry)],
            referenceDate: referenceDate,
            calendar: calendar,
            now: now
        )

        #expect(plans.count == 1)
        #expect(plans.first?.deliveryComponents.hour == 9)
        #expect(plans.first?.deliveryComponents.day == 25)
    }

    @Test func renewalNotificationIdentityRemainsActiveAfterDeliveryTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let referenceDate = LocalDate(
            try #require(
                calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))
            ),
            calendar: calendar
        )
        let subscription = makeRenewingSubscription(expiry: referenceDate)
        let afterDelivery = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 24, hour: 12)
            )
        )

        #expect(
            RenewalNotificationPlan.plans(
                subscriptions: [subscription],
                referenceDate: referenceDate,
                calendar: calendar,
                now: afterDelivery
            ).isEmpty
        )
        #expect(
            RenewalNotificationPlan.activeIdentifiers(
                subscriptions: [subscription],
                referenceDate: referenceDate
            ) == Set([
                RenewalNotificationPlan.identifier(
                    subscriptionID: subscription.id,
                    expiry: referenceDate
                )
            ])
        )
    }

    @Test func renewalNotificationCleanupOnlyRemovesStaleManagedIdentifiers() {
        let active = RenewalNotificationPlan.identifierPrefix + "active"
        let stale = RenewalNotificationPlan.identifierPrefix + "stale"
        let unrelated = "another-app.notification"

        #expect(
            RenewalNotificationPlan.staleManagedIdentifiers(
                in: [active, stale, unrelated],
                activeIdentifiers: [active]
            ) == [stale]
        )
    }

    @MainActor
    @Test func confirmingAutomaticRenewalUpdatesCurrentPeriodAndAppendsHistoryOnce() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let store = SubscriptionStore(modelContainer: container)
        let expiry = LocalDate.today
        let input = SubscriptionCreateInput(
            id: UUID(),
            name: "Renewing",
            symbolName: "arrow.clockwise",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: try #require(expiry.addingMonths(0)?.addingDays(-29)),
            expiry: expiry,
            cycleMonths: 1,
            money: Money(minorUnits: 2_000, currency: .usd),
            note: "",
            reminderEnabled: true,
            automaticallyRenews: true
        )
        _ = try await store.create(input)
        let current = try #require(try await store.fetchAll().first)
        let request = SubscriptionRenewalRequest(
            subscriptionID: current.id,
            expectedRevision: current.revision,
            expectedExpiry: expiry
        )

        let preview = try await store.confirmAutomaticRenewal(request, referenceDate: expiry)
        let updated = try #require(try await store.fetchAll().first)
        let periods = try await store.fetchPeriods(for: current.id)

        #expect(updated.periodStart == preview.nextStart)
        #expect(updated.expiry == preview.nextExpiry)
        #expect(updated.revision == current.revision + 1)
        #expect(periods.count == 2)
        #expect(periods.first?.source == .initial)
        #expect(periods.last?.source == .renewal)
        await #expect(throws: SubscriptionStore.StoreError.self) {
            try await store.confirmAutomaticRenewal(request, referenceDate: expiry)
        }
        #expect(try await store.fetchPeriods(for: current.id).count == 2)
    }

    @MainActor
    @Test func invalidSubscriptionDoesNotHideValidSubscriptions() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self]),
            inMemory: true
        )
        let validInput = SubscriptionCreateInput(
            id: UUID(),
            name: "Valid",
            symbolName: "checkmark",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: nil,
            expiry: nil,
            cycleMonths: 1,
            money: Money(minorUnits: 100, currency: .cny),
            note: "",
            reminderEnabled: true
        )
        let valid = SubscriptionRecord(input: validInput)
        let invalid = SubscriptionRecord(input: validInput)
        invalid.id = UUID()
        invalid.name = "Invalid"
        invalid.categoryRaw = "unknown-category"
        container.mainContext.insert(valid)
        container.mainContext.insert(invalid)
        try container.mainContext.save()
        let store = SubscriptionStore(modelContainer: container)

        let subscriptions = try await store.fetchAll()

        #expect(subscriptions.map(\.name) == ["Valid"])
    }

    @MainActor
    @Test func createdSubscriptionCanBeFetched() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let store = SubscriptionStore(modelContainer: container)
        let input = SubscriptionCreateInput(
            id: UUID(),
            name: "哔哩哔哩",
            symbolName: "play.rectangle.fill",
            iconResourceName: nil,
            iconURLString: nil,
            category: .media,
            managementState: .active,
            billingKind: .recurring,
            periodStart: nil,
            expiry: LocalDate(dayNumber: LocalDate.today.dayNumber + 22),
            cycleMonths: 1,
            money: try Money.parse("0", currency: .cny),
            note: "",
            reminderEnabled: true
        )

        _ = try await store.create(input)
        let records = try await store.fetchAll()

        #expect(records.count == 1)
        #expect(records.first?.name == "哔哩哔哩")
        #expect(records.first?.expiry == input.expiry)
    }

    @MainActor
    @Test func createdSubscriptionSurvivesStoreReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = PersistenceController(storeURL: directory.appending(path: "subscriptions.store"))
        let input = SubscriptionCreateInput(
            id: UUID(),
            name: "Persistent",
            symbolName: "externaldrive",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .lifetime,
            periodStart: LocalDate.today,
            expiry: nil,
            cycleMonths: nil,
            money: try Money.parse("199", currency: .cny),
            note: "",
            reminderEnabled: false
        )

        do {
            let container = try controller.makeContainer(
                schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self])
            )
            let store = SubscriptionStore(modelContainer: container)
            _ = try await store.create(input)
        }

        let reopened = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self])
        )
        let reopenedStore = SubscriptionStore(modelContainer: reopened)
        let records = try await reopenedStore.fetchAll()
        #expect(records.map(\.id) == [input.id])
        #expect(records.first?.billingKind == .lifetime)
        let periods = try await reopenedStore.fetchPeriods(for: input.id)
        #expect(periods.count == 1)
        #expect(periods.first?.start == input.periodStart)
        #expect(periods.first?.end == .defaultLifetimeHistoryEnd)
    }

    @MainActor
    @Test func editingCurrentPeriodCanOptionallyAppendHistoryAtomically() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let store = SubscriptionStore(modelContainer: container)
        let subscriptionID = UUID()
        let initialStart = LocalDate.today
        let initial = SubscriptionCreateInput(
            id: subscriptionID,
            name: "Optional History",
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: initialStart,
            expiry: LocalDate(dayNumber: initialStart.dayNumber + 29),
            cycleMonths: 1,
            money: try Money.parse("20", currency: .usd),
            note: "",
            reminderEnabled: true
        )
        _ = try await store.create(initial)

        let created = try #require(try await store.fetchAll().first)
        let currentOnlyStart = LocalDate(dayNumber: initialStart.dayNumber + 30)
        let currentOnly = SubscriptionCreateInput(
            id: subscriptionID,
            name: initial.name,
            symbolName: initial.symbolName,
            iconResourceName: nil,
            iconURLString: nil,
            category: initial.category,
            managementState: initial.managementState,
            billingKind: .recurring,
            periodStart: currentOnlyStart,
            expiry: LocalDate(dayNumber: currentOnlyStart.dayNumber + 29),
            cycleMonths: 1,
            money: initial.money,
            note: "",
            reminderEnabled: true
        )
        try await store.update(
            currentOnly,
            expectedRevision: created.revision,
            historyPolicy: .currentOnly
        )
        #expect(try await store.fetchPeriods(for: subscriptionID).count == 1)

        let current = try #require(try await store.fetchAll().first)
        let recordedStart = LocalDate(dayNumber: currentOnlyStart.dayNumber + 30)
        let recorded = SubscriptionCreateInput(
            id: subscriptionID,
            name: currentOnly.name,
            symbolName: currentOnly.symbolName,
            iconResourceName: nil,
            iconURLString: nil,
            category: currentOnly.category,
            managementState: currentOnly.managementState,
            billingKind: .recurring,
            periodStart: recordedStart,
            expiry: LocalDate(dayNumber: recordedStart.dayNumber + 29),
            cycleMonths: 1,
            money: currentOnly.money,
            note: "",
            reminderEnabled: true
        )
        try await store.update(
            recorded,
            expectedRevision: current.revision,
            historyPolicy: .appendPeriodRecord
        )

        let periods = try await store.fetchPeriods(for: subscriptionID)
        #expect(periods.count == 2)
        #expect(periods.first?.source == .initial)
        #expect(periods.last?.source == .manual)
        #expect(periods.last?.start == recorded.periodStart)
        #expect(periods.last?.end == recorded.expiry)
        let finalSubscription = try #require(try await store.fetchAll().first)
        #expect(finalSubscription.revision == current.revision + 1)
    }

    @MainActor
    @Test func existingLifetimeSubscriptionWithoutHistoryIsBackfilled() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let subscriptionID = UUID()
        let input = SubscriptionCreateInput(
            id: subscriptionID,
            name: "Existing Lifetime",
            symbolName: "infinity",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .lifetime,
            periodStart: nil,
            expiry: nil,
            cycleMonths: nil,
            money: try Money.parse("99", currency: .cny),
            note: "",
            reminderEnabled: false
        )
        container.mainContext.insert(SubscriptionRecord(input: input))
        try container.mainContext.save()
        let store = SubscriptionStore(modelContainer: container)

        #expect(try await store.backfillLifetimePeriods() == 1)
        #expect(try await store.backfillLifetimePeriods() == 0)
        let period = try #require(try await store.fetchPeriods(for: subscriptionID).first)
        #expect(period.end == .defaultLifetimeHistoryEnd)
        #expect(period.source == .initial)
    }

    @MainActor
    @Test func changingExistingSubscriptionToLifetimeUsesCreationDateForHistory() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let subscriptionID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_705_000_000)
        let original = SubscriptionCreateInput(
            id: subscriptionID,
            name: "Existing",
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: nil,
            expiry: nil,
            cycleMonths: 1,
            money: try Money.parse("99", currency: .cny),
            note: "",
            reminderEnabled: true
        )
        container.mainContext.insert(SubscriptionRecord(input: original, now: createdAt))
        try container.mainContext.save()
        let store = SubscriptionStore(modelContainer: container)
        let lifetime = SubscriptionCreateInput(
            id: subscriptionID,
            name: original.name,
            symbolName: original.symbolName,
            iconResourceName: nil,
            iconURLString: nil,
            category: original.category,
            managementState: original.managementState,
            billingKind: .lifetime,
            periodStart: nil,
            expiry: nil,
            cycleMonths: nil,
            money: original.money,
            note: "",
            reminderEnabled: false
        )

        try await store.update(
            lifetime,
            expectedRevision: 1,
            historyPolicy: .currentOnly
        )

        let period = try #require(try await store.fetchPeriods(for: subscriptionID).first)
        #expect(period.start == LocalDate(createdAt))
        #expect(period.end == .defaultLifetimeHistoryEnd)
    }

    @MainActor
    @Test func lifetimeBackfillSkipsInvalidCurrencyWithoutRollingBackValidRepairs() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([SubscriptionRecord.self, SubscriptionPeriodRecord.self]),
            inMemory: true
        )
        let validID = UUID()
        let invalidID = UUID()
        let existingPeriodID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_705_000_000)
        let money = try Money.parse("99", currency: .cny)

        func lifetimeInput(id: UUID, name: String) -> SubscriptionCreateInput {
            SubscriptionCreateInput(
                id: id,
                name: name,
                symbolName: "infinity",
                iconResourceName: nil,
                iconURLString: nil,
                category: .tools,
                managementState: .active,
                billingKind: .lifetime,
                periodStart: nil,
                expiry: nil,
                cycleMonths: nil,
                money: money,
                note: "",
                reminderEnabled: false
            )
        }

        container.mainContext.insert(
            SubscriptionRecord(input: lifetimeInput(id: validID, name: "Valid"), now: createdAt)
        )
        let invalidRecord = SubscriptionRecord(
            input: lifetimeInput(id: invalidID, name: "Invalid"),
            now: createdAt
        )
        invalidRecord.currencyCode = "INVALID"
        container.mainContext.insert(invalidRecord)
        container.mainContext.insert(
            SubscriptionPeriodRecord(
                input: SubscriptionPeriodCreateInput(
                    id: existingPeriodID,
                    subscriptionID: UUID(),
                    billingKind: .lifetime,
                    cycleMonths: nil,
                    start: LocalDate(createdAt),
                    end: nil,
                    money: money
                )
            )
        )
        try container.mainContext.save()
        let store = SubscriptionStore(modelContainer: container)

        #expect(try await store.backfillLifetimePeriods() == 2)
        #expect(try await store.backfillLifetimePeriods() == 0)
        let inserted = try #require(try await store.fetchPeriods(for: validID).first)
        #expect(inserted.start == LocalDate(createdAt))
        #expect(inserted.end == .defaultLifetimeHistoryEnd)
        #expect(try await store.fetchPeriods(for: invalidID).isEmpty)

        let repairedDescriptor = FetchDescriptor<SubscriptionPeriodRecord>(
            predicate: #Predicate { $0.id == existingPeriodID }
        )
        let repaired = try #require(container.mainContext.fetch(repairedDescriptor).first)
        #expect(repaired.endDay == LocalDate.defaultLifetimeHistoryEnd.dayNumber)
    }

    @MainActor
    @Test func userTemplateCanBeCreatedUpdatedAndDeleted() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([ServiceTemplateRecord.self]),
            inMemory: true
        )
        let store = TemplateStore(modelContainer: container)
        let id = UUID()
        let initial = ServiceTemplateInput(
            id: id,
            expectedRevision: nil,
            name: "ChatGPT",
            aliases: ["OpenAI", "openai"],
            category: .tools,
            customCategoryID: nil,
            symbolName: "bubble.left.and.text.bubble.right",
            iconResourceName: "chatgpt.jpg",
            iconURLString: "https://is1-ssl.mzstatic.com/image/thumb/example/512x512bb.jpg",
            suggestedBillingKind: .recurring,
            suggestedCycleMonths: 1,
            suggestedMoney: try Money.parse("20", currency: .usd),
            currency: .usd
        )

        try await store.save(initial)
        let created = try #require(try await store.fetchAll().first)
        #expect(created.key == .user(id))
        #expect(created.aliases == ["OpenAI"])
        #expect(created.iconResourceName == "chatgpt.jpg")
        #expect(created.revision == 1)

        let updated = ServiceTemplateInput(
            id: id,
            expectedRevision: created.revision,
            name: "ChatGPT Plus",
            aliases: created.aliases,
            category: created.category,
            customCategoryID: created.customCategoryID,
            symbolName: created.symbolName,
            iconResourceName: created.iconResourceName,
            iconURLString: created.iconURLString,
            suggestedBillingKind: created.suggestedBillingKind,
            suggestedCycleMonths: created.suggestedCycleMonths,
            suggestedMoney: created.suggestedMoney,
            currency: created.currency
        )
        try await store.save(updated)
        let saved = try #require(try await store.fetchAll().first)
        #expect(saved.name == "ChatGPT Plus")
        #expect(saved.revision == 2)

        try await store.delete(id: id, expectedRevision: 2)
        #expect(try await store.fetchAll().isEmpty)
    }

    @MainActor
    @Test func customTemplateCategoryPersistsAndDeletionMovesTemplatesToOther() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([
                ServiceTemplateRecord.self,
                TemplateCategoryRecord.self,
                BuiltinTemplateCategoryAssignmentRecord.self,
            ]),
            inMemory: true
        )
        let categoryStore = TemplateCategoryStore(modelContainer: container)
        let templateStore = TemplateStore(modelContainer: container)
        let builtinCategoryStore = BuiltinTemplateCategoryStore(modelContainer: container)
        let categoryID = UUID()

        try await categoryStore.save(
            TemplateCategoryInput(id: categoryID, expectedRevision: nil, name: "效率服务")
        )
        let category = try #require(try await categoryStore.fetchAll().first)
        #expect(category.name == "效率服务")

        try await templateStore.save(
            ServiceTemplateInput(
                id: UUID(),
                expectedRevision: nil,
                name: "自定义服务",
                aliases: [],
                category: .other,
                customCategoryID: categoryID,
                symbolName: "square.stack.3d.up",
                iconResourceName: nil,
                iconURLString: nil,
                suggestedBillingKind: .recurring,
                suggestedCycleMonths: 1,
                suggestedMoney: nil,
                currency: .cny
            )
        )
        try await builtinCategoryStore.assign(
            .custom(categoryID),
            toBuiltinTemplate: "chatgpt"
        )

        try await categoryStore.delete(id: categoryID, expectedRevision: category.revision)
        #expect(try await categoryStore.fetchAll().isEmpty)
        let template = try #require(try await templateStore.fetchAll().first)
        #expect(template.customCategoryID == nil)
        #expect(template.category == .other)
        #expect(template.revision == 2)
        #expect(
            try await builtinCategoryStore.fetchAssignments()["chatgpt"]
                == .builtin(.other)
        )

        do {
            try await templateStore.save(
                ServiceTemplateInput(
                    id: UUID(),
                    expectedRevision: nil,
                    name: "悬空分类模板",
                    aliases: [],
                    category: .other,
                    customCategoryID: categoryID,
                    symbolName: "questionmark.folder",
                    iconResourceName: nil,
                    iconURLString: nil,
                    suggestedBillingKind: .recurring,
                    suggestedCycleMonths: 1,
                    suggestedMoney: nil,
                    currency: .cny
                )
            )
            Issue.record("不应允许模板引用已删除的分类。")
        } catch TemplateStore.StoreError.categoryNotFound {
            // Expected: stale editors cannot create an orphaned category reference.
        }
    }

    @MainActor
    @Test func invalidBuiltinCategoryAssignmentDoesNotHideValidAssignments() async throws {
        let controller = PersistenceController()
        let container = try controller.makeContainer(
            schema: Schema([BuiltinTemplateCategoryAssignmentRecord.self]),
            inMemory: true
        )
        let valid = BuiltinTemplateCategoryAssignmentRecord(
            templateKey: "chatgpt",
            assignment: .builtin(.tools)
        )
        let invalid = BuiltinTemplateCategoryAssignmentRecord(
            templateKey: "broken",
            assignment: .builtin(.other)
        )
        invalid.categoryRaw = "not-a-category"
        container.mainContext.insert(valid)
        container.mainContext.insert(invalid)
        try container.mainContext.save()
        let store = BuiltinTemplateCategoryStore(modelContainer: container)

        let assignments = try await store.fetchAssignments()

        #expect(assignments == ["chatgpt": .builtin(.tools)])
    }

    @Test func missingIconPlaceholderIsStableForAServiceName() {
        let first = PlaceholderSymbolResolver.symbol(for: "Setapp")
        let second = PlaceholderSymbolResolver.symbol(for: "Setapp")

        #expect(first == second)
        #expect(!first.isEmpty)
    }

    private func makeRenewingSubscription(expiry: LocalDate) -> SubscriptionDTO {
        SubscriptionDTO(
            id: UUID(),
            name: "Renewing",
            symbolName: "arrow.clockwise",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: expiry.addingDays(-29),
            expiry: expiry,
            cycleMonths: 1,
            money: Money(minorUnits: 2_000, currency: .usd),
            note: "",
            reminderEnabled: true,
            automaticallyRenews: true,
            revision: 1,
            createdAt: .now,
            updatedAt: .now
        )
    }
}
