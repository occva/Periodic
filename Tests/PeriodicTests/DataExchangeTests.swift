import Foundation
import SwiftData
import Testing
@testable import Periodic

struct DataExchangeTests {
    @Test func dataPackageRoundTripsAndDetectsTampering() throws {
        let snapshot = makeSnapshot()
        let encoded = try DataPackageCodec.encode(
            snapshot: snapshot,
            assets: [:],
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try DataPackageCodec.decode(
            fileWrapper: DataPackageCodec.fileWrapper(for: encoded)
        )

        #expect(decoded.snapshot == snapshot)
        #expect(decoded.manifest.tables.subscriptions == 1)
        #expect(decoded.manifest.tables.periods == 1)

        var changedFiles = encoded.files
        changedFiles["data/subscriptions.jsonl"]?.append(Data("tampered".utf8))
        let tampered = EncodedDataPackage(
            files: changedFiles,
            preferredFilename: encoded.preferredFilename
        )
        #expect(throws: DataExchangeError.self) {
            try DataPackageCodec.decode(
                fileWrapper: DataPackageCodec.fileWrapper(for: tampered)
            )
        }
    }

    @MainActor
    @Test func mergeImportIsAtomicAndBecomesIdempotent() async throws {
        let sourceContainer = try makeContainer()
        let sourceStore = SubscriptionStore(modelContainer: sourceContainer)
        _ = try await sourceStore.create(makeSubscriptionInput())
        let categoryID = UUID()
        let categoryInput = TemplateCategoryInput(
            id: categoryID,
            expectedRevision: nil,
            name: "Imported Category"
        )
        sourceContainer.mainContext.insert(TemplateCategoryRecord(input: categoryInput))
        let templateInput = ServiceTemplateInput(
            id: UUID(),
            expectedRevision: nil,
            name: "Imported Template",
            aliases: ["Alias"],
            category: .other,
            customCategoryID: categoryID,
            symbolName: "square.grid.2x2",
            iconResourceName: nil,
            iconURLString: nil,
            suggestedBillingKind: .recurring,
            suggestedCycleMonths: 1,
            suggestedMoney: Money(minorUnits: 999, currency: .usd),
            currency: .usd
        )
        sourceContainer.mainContext.insert(
            ServiceTemplateRecord(
                input: templateInput,
                aliasesData: try JSONEncoder().encode(templateInput.aliases)
            )
        )
        sourceContainer.mainContext.insert(
            BuiltinTemplateCategoryAssignmentRecord(
                templateKey: "chatgpt",
                assignment: .custom(categoryID)
            )
        )
        try sourceContainer.mainContext.save()
        let imported = try await DataExchangeStore(modelContainer: sourceContainer).snapshot()

        let targetContainer = try makeContainer()
        let exchangeStore = DataExchangeStore(modelContainer: targetContainer)
        let targetDigest = try await exchangeStore.digest()
        let firstPreview = try await exchangeStore.preview(imported: imported)
        #expect(firstPreview.subscriptions.additions == 1)
        #expect(firstPreview.periods.additions == 1)
        #expect(firstPreview.templates.additions == 1)
        #expect(firstPreview.categories.additions == 1)
        #expect(firstPreview.assignments.additions == 1)

        let receipt = try await exchangeStore.execute(
            imported: imported,
            expectedDigest: targetDigest,
            conflictResolution: .keepLocal
        )
        #expect(receipt.added == 5)
        #expect(receipt.updated == 0)

        let secondPreview = try await exchangeStore.preview(imported: imported)
        #expect(secondPreview.subscriptions.unchanged == 1)
        #expect(secondPreview.periods.unchanged == 1)
        #expect(secondPreview.templates.unchanged == 1)
        #expect(secondPreview.categories.unchanged == 1)
        #expect(secondPreview.assignments.unchanged == 1)
        #expect(secondPreview.subscriptions.conflicts == 0)
        #expect(secondPreview.periods.conflicts == 0)
    }

    @MainActor
    @Test func importPlanRejectsTargetChangesAfterPreview() async throws {
        let container = try makeContainer()
        let exchangeStore = DataExchangeStore(modelContainer: container)
        let originalDigest = try await exchangeStore.digest()
        let subscriptionStore = SubscriptionStore(modelContainer: container)
        _ = try await subscriptionStore.create(makeSubscriptionInput())

        await #expect(throws: DataExchangeError.self) {
            try await exchangeStore.execute(
                imported: .empty,
                expectedDigest: originalDigest,
                conflictResolution: .keepLocal
            )
        }
        #expect(try await subscriptionStore.fetchAll().count == 1)
    }

    @Test func packageRejectsUnreferencedAssetsAndInvalidSettings() throws {
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let identifier = DataPackageCodec.sha256(imageData)

        #expect(throws: DataExchangeError.self) {
            try DataPackageCodec.encode(
                snapshot: makeSnapshot(),
                assets: [identifier: imageData]
            )
        }

        var invalidSettingsSnapshot = makeSnapshot()
        invalidSettingsSnapshot.settings = DataPackageSettings(
            appearance: "unsupported",
            language: AppLanguage.system.rawValue,
            defaultCurrency: CurrencyCode.cny.rawValue,
            selectedCurrencies: CurrencyCode.cny.rawValue,
            usesCurrencySymbols: false,
            menuBarEnabled: true,
            menuBarDueHorizon: DueHorizon.fifteenDays.rawValue,
            menuBarShowsForecasts: true,
            exchangeRateBaseCurrency: CurrencyCode.cny.rawValue
        )
        #expect(throws: DataExchangeError.self) {
            try DataPackageCodec.encode(snapshot: invalidSettingsSnapshot, assets: [:])
        }
    }

    @MainActor
    @Test func failedImportRemovesNewlyPersistedImages() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storageRoot) }

        let container = try makeContainer()
        let store = DataExchangeStore(modelContainer: container)
        let targetDigest = try await store.digest()
        _ = try await SubscriptionStore(modelContainer: container).create(makeSubscriptionInput())

        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let identifier = DataPackageCodec.sha256(imageData)
        var snapshot = makeSnapshot()
        snapshot.subscriptions[0].iconAssetID = identifier
        let manifest = DataPackageManifest(
            format: DataPackageManifest.currentFormat,
            formatVersion: DataPackageManifest.currentVersion,
            minimumReaderVersion: DataPackageManifest.currentVersion,
            exportID: UUID(),
            sourceDatasetID: UUID(),
            createdAt: .now,
            appVersion: "test",
            calendar: "gregorian",
            scope: "full",
            tables: .init(
                subscriptions: 1,
                periods: 1,
                templates: 0,
                categories: 0,
                builtinCategoryAssignments: 0
            ),
            assetCount: 1,
            includesSettings: false
        )
        let package = DecodedDataPackage(
            manifest: manifest,
            snapshot: snapshot,
            assets: [identifier: imageData],
            sourceDigest: "test"
        )
        let plan = DataImportPlan(
            id: UUID(),
            package: package,
            targetDigest: targetDigest,
            preview: try await store.preview(imported: snapshot),
            expiresAt: Date().addingTimeInterval(60)
        )
        let service = DataExchangeService(
            store: store,
            iconCache: AppleIconCache(storageRoot: storageRoot)
        )

        await #expect(throws: DataExchangeError.self) {
            try await service.execute(
                plan: plan,
                conflictResolution: .useImported,
                importsSettings: false
            )
        }
        let storedImage = storageRoot
            .appending(path: "UserServiceIcons", directoryHint: .isDirectory)
            .appending(path: identifier)
            .appendingPathExtension("image")
        #expect(!FileManager.default.fileExists(atPath: storedImage.path))
    }

    private func makeSnapshot() -> DataPackageSnapshot {
        let subscriptionID = UUID()
        let periodID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        return DataPackageSnapshot(
            subscriptions: [
                DataPackageSubscription(
                    recordVersion: 1,
                    id: subscriptionID,
                    name: "Example, Inc.",
                    symbolName: "calendar",
                    iconResourceName: nil,
                    iconAssetID: nil,
                    category: .tools,
                    managementState: .active,
                    billingKind: .recurring,
                    periodStart: LocalDate(dayNumber: 20_000),
                    expiry: LocalDate(dayNumber: 20_029),
                    cycleMonths: 1,
                    amountMinor: 1_999,
                    currency: .usd,
                    currencyScale: 2,
                    note: "Unicode 备注\n第二行",
                    reminderEnabled: true,
                    automaticallyRenews: true,
                    revision: 4,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            ],
            periods: [
                DataPackagePeriod(
                    recordVersion: 1,
                    id: periodID,
                    subscriptionID: subscriptionID,
                    billingKind: .recurring,
                    cycleMonths: 1,
                    start: LocalDate(dayNumber: 20_000),
                    end: LocalDate(dayNumber: 20_029),
                    amountMinor: 1_999,
                    currency: .usd,
                    currencyScale: 2,
                    source: .initial,
                    createdAt: timestamp
                )
            ],
            templates: [],
            categories: [],
            builtinCategoryAssignments: [],
            settings: nil
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController().makeContainer(
            schema: Schema([
                SubscriptionRecord.self,
                SubscriptionPeriodRecord.self,
                ServiceTemplateRecord.self,
                TemplateCategoryRecord.self,
                BuiltinTemplateCategoryAssignmentRecord.self,
            ]),
            inMemory: true
        )
    }

    private func makeSubscriptionInput() -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: UUID(),
            name: "Imported",
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: LocalDate(dayNumber: 20_000),
            expiry: LocalDate(dayNumber: 20_029),
            cycleMonths: 1,
            money: Money(minorUnits: 1_999, currency: .usd),
            note: "",
            reminderEnabled: true,
            automaticallyRenews: true
        )
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
