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
        #expect(try await reopenedStore.fetchPeriods(for: input.id).count == 1)
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
            schema: Schema([ServiceTemplateRecord.self, TemplateCategoryRecord.self]),
            inMemory: true
        )
        let categoryStore = TemplateCategoryStore(modelContainer: container)
        let templateStore = TemplateStore(modelContainer: container)
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

        try await categoryStore.delete(id: categoryID, expectedRevision: category.revision)
        #expect(try await categoryStore.fetchAll().isEmpty)
        let template = try #require(try await templateStore.fetchAll().first)
        #expect(template.customCategoryID == nil)
        #expect(template.category == .other)
        #expect(template.revision == 2)
    }

    @Test func missingIconPlaceholderIsStableForAServiceName() {
        let first = PlaceholderSymbolResolver.symbol(for: "Setapp")
        let second = PlaceholderSymbolResolver.symbol(for: "Setapp")

        #expect(first == second)
        #expect(!first.isEmpty)
    }
}
