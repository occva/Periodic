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
        #expect(decoded.manifest.tables.payments == 1)

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

    @Test func renewalPaymentWithoutCoverageSnapshotIsRejected() throws {
        var snapshot = makeSnapshot()
        let payment = try #require(snapshot.payments.first)
        snapshot.payments = [
            DataPackagePayment(
                recordVersion: payment.recordVersion,
                id: payment.id,
                subscriptionID: payment.subscriptionID,
                periodRecordID: nil,
                kind: .renewal,
                paymentDate: payment.paymentDate,
                amountMinor: payment.amountMinor,
                currency: payment.currency,
                currencyScale: payment.currencyScale,
                periodStart: nil,
                periodEnd: nil,
                note: payment.note,
                attachmentAssetIDs: [],
                revision: payment.revision,
                createdAt: payment.createdAt,
                updatedAt: payment.updatedAt
            ),
        ]

        #expect(throws: DataExchangeError.self) {
            try DataPackageCodec.encode(snapshot: snapshot, assets: [:])
        }
    }

    @Test func dataPackageIncludesOrderedPaymentScreenshotAssets() throws {
        let firstImageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let secondImageData = firstImageData + Data([0])
        let firstIdentifier = DataPackageCodec.sha256(firstImageData)
        let secondIdentifier = DataPackageCodec.sha256(secondImageData)
        var snapshot = makeSnapshot()
        snapshot.payments[0].attachmentAssetIDs = [secondIdentifier, firstIdentifier]

        let encoded = try DataPackageCodec.encode(
            snapshot: snapshot,
            assets: [
                firstIdentifier: firstImageData,
                secondIdentifier: secondImageData,
            ]
        )
        let decoded = try DataPackageCodec.decode(
            fileWrapper: DataPackageCodec.fileWrapper(for: encoded)
        )

        #expect(
            decoded.snapshot.payments.first?.attachmentAssetIDs
                == [secondIdentifier, firstIdentifier]
        )
        #expect(decoded.assets[firstIdentifier] == firstImageData)
        #expect(decoded.assets[secondIdentifier] == secondImageData)
        #expect(decoded.manifest.formatVersion == 5)
    }

    @Test func versionTwoPaymentWithoutScreenshotFieldRemainsReadable() throws {
        let encoded = try DataPackageCodec.encode(snapshot: makeSnapshot(), assets: [:])
        var files = encoded.files
        let paymentData = try #require(files["data/payments.jsonl"])
        var payment = try #require(
            JSONSerialization.jsonObject(with: paymentData) as? [String: Any]
        )
        payment.removeValue(forKey: "attachmentAssetIDs")
        files["data/payments.jsonl"] = try JSONSerialization.data(withJSONObject: payment)
            + Data("\n".utf8)

        let manifestData = try #require(files["manifest.json"])
        var manifest = try #require(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        manifest["formatVersion"] = 2
        manifest["minimumReaderVersion"] = 2
        files["manifest.json"] = try JSONSerialization.data(withJSONObject: manifest)
        let checksums = Dictionary(
            uniqueKeysWithValues: files
                .filter { $0.key != "checksums.json" }
                .map { ($0.key, DataPackageCodec.sha256($0.value)) }
        )
        files["checksums.json"] = try JSONEncoder().encode(checksums)

        let decoded = try DataPackageCodec.decode(
            fileWrapper: DataPackageCodec.fileWrapper(
                for: EncodedDataPackage(
                    files: files,
                    preferredFilename: "V2.periodicdata"
                )
            )
        )
        #expect(decoded.manifest.formatVersion == 2)
        #expect(decoded.snapshot.payments.first?.attachmentAssetIDs == [])
    }

    @Test func versionThreeSinglePaymentScreenshotRemainsReadable() throws {
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let identifier = DataPackageCodec.sha256(imageData)
        var snapshot = makeSnapshot()
        snapshot.payments[0].attachmentAssetIDs = [identifier]
        let encoded = try DataPackageCodec.encode(
            snapshot: snapshot,
            assets: [identifier: imageData]
        )
        var files = encoded.files
        let paymentData = try #require(files["data/payments.jsonl"])
        var payment = try #require(
            JSONSerialization.jsonObject(with: paymentData) as? [String: Any]
        )
        payment["attachmentAssetID"] = identifier
        payment.removeValue(forKey: "attachmentAssetIDs")
        files["data/payments.jsonl"] = try JSONSerialization.data(withJSONObject: payment)
            + Data("\n".utf8)

        let manifestData = try #require(files["manifest.json"])
        var manifest = try #require(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        manifest["formatVersion"] = 3
        manifest["minimumReaderVersion"] = 3
        files["manifest.json"] = try JSONSerialization.data(withJSONObject: manifest)
        let checksums = Dictionary(
            uniqueKeysWithValues: files
                .filter { $0.key != "checksums.json" }
                .map { ($0.key, DataPackageCodec.sha256($0.value)) }
        )
        files["checksums.json"] = try JSONEncoder().encode(checksums)

        let decoded = try DataPackageCodec.decode(
            fileWrapper: DataPackageCodec.fileWrapper(
                for: EncodedDataPackage(
                    files: files,
                    preferredFilename: "V3.periodicdata"
                )
            )
        )

        #expect(decoded.manifest.formatVersion == 3)
        #expect(decoded.snapshot.payments.first?.attachmentAssetIDs == [identifier])
    }

    @MainActor
    @Test func paymentScreenshotsRoundTripThroughDataExchangeService() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let targetRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let firstImageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let secondImageData = firstImageData + Data([0])

        let sourceContainer = try makeContainer()
        let sourceSubscriptionStore = SubscriptionStore(modelContainer: sourceContainer)
        let input = makeSubscriptionInput()
        _ = try await sourceSubscriptionStore.create(input)
        let subscription = try #require(try await sourceSubscriptionStore.fetchAll().first)
        let sourceAttachmentStore = PaymentAttachmentStore(storageRoot: sourceRoot)
        let firstWrite = try await sourceAttachmentStore.persistImportedImage(firstImageData)
        let secondWrite = try await sourceAttachmentStore.persistImportedImage(secondImageData)
        try await sourceSubscriptionStore.addPayment(
            SubscriptionPaymentAddInput(
                payment: SubscriptionPaymentCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    periodRecordID: nil,
                    kind: .manual,
                    paymentDate: .today,
                    money: input.money,
                    periodStart: nil,
                    periodEnd: nil,
                    note: "带截图",
                    attachmentReferences: [secondWrite.reference, firstWrite.reference]
                ),
                expectedSubscriptionRevision: subscription.revision
            )
        )
        let sourceService = DataExchangeService(
            store: DataExchangeStore(modelContainer: sourceContainer),
            iconCache: AppleIconCache(storageRoot: sourceRoot),
            paymentAttachmentStore: sourceAttachmentStore
        )
        let encoded = try await sourceService.prepareExport()
        let decoded = try DataPackageCodec.decode(
            fileWrapper: DataPackageCodec.fileWrapper(for: encoded)
        )
        let assetIDs = try #require(decoded.snapshot.payments.first?.attachmentAssetIDs)
        #expect(assetIDs.count == 2)
        #expect(decoded.assets[assetIDs[0]] == secondImageData)
        #expect(decoded.assets[assetIDs[1]] == firstImageData)

        let targetContainer = try makeContainer()
        let targetExchangeStore = DataExchangeStore(modelContainer: targetContainer)
        let targetAttachmentStore = PaymentAttachmentStore(storageRoot: targetRoot)
        let targetService = DataExchangeService(
            store: targetExchangeStore,
            iconCache: AppleIconCache(storageRoot: targetRoot),
            paymentAttachmentStore: targetAttachmentStore
        )
        let plan = DataImportPlan(
            id: UUID(),
            package: decoded,
            targetDigest: try await targetExchangeStore.digest(),
            preview: try await targetExchangeStore.preview(imported: decoded.snapshot),
            expiresAt: Date().addingTimeInterval(60)
        )
        _ = try await targetService.execute(
            plan: plan,
            conflictResolution: .useImported,
            importsSettings: false
        )

        let importedPayment = try #require(
            try await SubscriptionStore(modelContainer: targetContainer)
                .fetchPayments(for: subscription.id)
                .first
        )
        #expect(importedPayment.attachmentReferences.count == 2)
        #expect(
            try await targetAttachmentStore.data(
                for: importedPayment.attachmentReferences[0]
            ) == secondImageData
        )
        #expect(
            try await targetAttachmentStore.data(
                for: importedPayment.attachmentReferences[1]
            ) == firstImageData
        )
    }

    @MainActor
    @Test func assetPreviewCountsReferencedFilesWithoutPreparingPackage() async throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let imageData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let iconCache = AppleIconCache(storageRoot: storageRoot)
        let attachmentStore = PaymentAttachmentStore(
            storageRoot: storageRoot
        )
        let iconWrite = try await iconCache.persistImportedImage(imageData)
        await iconCache.releaseImportedImages([iconWrite])
        let attachmentWrite = try await attachmentStore.persistImportedImage(
            imageData
        )
        await attachmentStore.releaseImportedImages([attachmentWrite])

        let container = try makeContainer()
        let subscriptionStore = SubscriptionStore(
            modelContainer: container
        )
        let base = makeSubscriptionInput()
        let input = SubscriptionCreateInput(
            id: base.id,
            name: base.name,
            symbolName: base.symbolName,
            iconResourceName: nil,
            iconURLString: iconWrite.reference,
            category: base.category,
            managementState: base.managementState,
            billingKind: base.billingKind,
            periodStart: base.periodStart,
            expiry: base.expiry,
            cycleMonths: base.cycleMonths,
            money: base.money,
            note: base.note,
            reminderEnabled: base.reminderEnabled,
            automaticallyRenews: base.automaticallyRenews
        )
        _ = try await subscriptionStore.create(input)
        let subscription = try #require(
            try await subscriptionStore.fetchAll().first
        )
        try await subscriptionStore.addPayment(
            SubscriptionPaymentAddInput(
                payment: SubscriptionPaymentCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    periodRecordID: nil,
                    kind: .manual,
                    paymentDate: .today,
                    money: input.money,
                    periodStart: nil,
                    periodEnd: nil,
                    note: "",
                    attachmentReferences: [attachmentWrite.reference]
                ),
                expectedSubscriptionRevision: subscription.revision
            )
        )
        let service = DataExchangeService(
            store: DataExchangeStore(modelContainer: container),
            iconCache: iconCache,
            paymentAttachmentStore: attachmentStore
        )

        let preview = try await service.previewAssets()

        #expect(preview.assetCount == 2)
        #expect(preview.estimatedBytes == Int64(imageData.count * 2))
    }

    @Test func legacySubscriptionWithoutReminderScheduleUsesImportDefaults() throws {
        let value = try #require(
            makeSnapshot(
                reminderAdvanceDays: SubscriptionNotificationSchedule.defaultAdvanceDays,
                reminderMinuteOfDay: SubscriptionNotificationSchedule.defaultMinuteOfDay
            ).subscriptions.first
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(value)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "reminderAdvanceDays")
        object.removeValue(forKey: "reminderMinuteOfDay")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            DataPackageSubscription.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.reminderAdvanceDays == nil)
        #expect(decoded.reminderMinuteOfDay == nil)
        #expect(decoded == value)
    }

    @Test func versionOnePackageWithoutPaymentsRemainsReadable() throws {
        var snapshot = makeSnapshot()
        snapshot.payments = []
        let encoded = try DataPackageCodec.encode(snapshot: snapshot, assets: [:])
        var files = encoded.files
        files.removeValue(forKey: "data/payments.jsonl")

        let manifestData = try #require(files["manifest.json"])
        var manifest = try #require(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        manifest["formatVersion"] = 1
        manifest["minimumReaderVersion"] = 1
        var tables = try #require(manifest["tables"] as? [String: Any])
        tables.removeValue(forKey: "payments")
        manifest["tables"] = tables
        files["manifest.json"] = try JSONSerialization.data(withJSONObject: manifest)

        let checksums = Dictionary(
            uniqueKeysWithValues: files
                .filter { $0.key != "checksums.json" }
                .map { ($0.key, DataPackageCodec.sha256($0.value)) }
        )
        files["checksums.json"] = try JSONEncoder().encode(checksums)
        let legacy = EncodedDataPackage(
            files: files,
            preferredFilename: "Legacy.periodicdata"
        )

        let decoded = try DataPackageCodec.decode(
            fileWrapper: DataPackageCodec.fileWrapper(for: legacy)
        )
        #expect(decoded.manifest.formatVersion == 1)
        #expect(decoded.snapshot.payments.isEmpty)
    }

    @MainActor
    @Test func legacyReminderDefaultsRemainIdempotentAfterImport() async throws {
        let imported = makeSnapshot(
            reminderAdvanceDays: nil,
            reminderMinuteOfDay: nil
        )
        let container = try makeContainer()
        let store = DataExchangeStore(modelContainer: container)
        let targetDigest = try await store.digest()

        _ = try await store.execute(
            imported: imported,
            expectedDigest: targetDigest,
            conflictResolution: .keepLocal
        )
        let preview = try await store.preview(imported: imported)

        #expect(preview.subscriptions.unchanged == 1)
        #expect(preview.subscriptions.conflicts == 0)
    }

    @MainActor
    @Test func mergeImportIsAtomicAndBecomesIdempotent() async throws {
        let sourceContainer = try makeContainer()
        let sourceStore = SubscriptionStore(modelContainer: sourceContainer)
        let subscriptionInput = makeSubscriptionInput()
        _ = try await sourceStore.create(subscriptionInput)
        let subscription = try #require(try await sourceStore.fetchAll().first)
        let period = try #require(try await sourceStore.fetchPeriods(for: subscription.id).first)
        try await sourceStore.addPayment(
            SubscriptionPaymentAddInput(
                payment: SubscriptionPaymentCreateInput(
                    id: UUID(),
                    subscriptionID: subscription.id,
                    periodRecordID: period.id,
                    kind: .initial,
                    paymentDate: period.start,
                    money: Money(minorUnits: 1_499, currency: .usd),
                    periodStart: period.start,
                    periodEnd: period.end,
                    note: "Imported payment",
                    attachmentReferences: []
                ),
                expectedSubscriptionRevision: subscription.revision
            )
        )
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
        #expect(firstPreview.payments.additions == 1)
        #expect(firstPreview.templates.additions == 1)
        #expect(firstPreview.categories.additions == 1)
        #expect(firstPreview.assignments.additions == 1)

        let receipt = try await exchangeStore.execute(
            imported: imported,
            expectedDigest: targetDigest,
            conflictResolution: .keepLocal
        )
        #expect(receipt.added == 6)
        #expect(receipt.updated == 0)

        let secondPreview = try await exchangeStore.preview(imported: imported)
        #expect(secondPreview.subscriptions.unchanged == 1)
        #expect(secondPreview.periods.unchanged == 1)
        #expect(secondPreview.payments.unchanged == 1)
        #expect(secondPreview.templates.unchanged == 1)
        #expect(secondPreview.categories.unchanged == 1)
        #expect(secondPreview.assignments.unchanged == 1)
        #expect(secondPreview.subscriptions.conflicts == 0)
        #expect(secondPreview.periods.conflicts == 0)
        #expect(secondPreview.payments.conflicts == 0)
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

    @MainActor
    @Test func importedHistoryAdvancesExistingOwnerRevisionOnlyWhenChanged() async throws {
        let container = try makeContainer()
        let subscriptionStore = SubscriptionStore(modelContainer: container)
        let exchangeStore = DataExchangeStore(modelContainer: container)
        let input = makeSubscriptionInput()
        _ = try await subscriptionStore.create(input)
        let original = try await subscriptionStore.fetchDetail(for: input.id)
        var imported = try await exchangeStore.snapshot()
        let extraPeriod = DataPackagePeriod(
            recordVersion: 1,
            id: UUID(),
            subscriptionID: input.id,
            billingKind: .recurring,
            cycleMonths: 1,
            start: LocalDate(dayNumber: 20_030),
            end: LocalDate(dayNumber: 20_059),
            amountMinor: 1_999,
            currency: .usd,
            currencyScale: 2,
            source: .manual,
            createdAt: Date()
        )
        imported.periods.append(extraPeriod)
        _ = try await exchangeStore.execute(
            imported: imported,
            expectedDigest: try await exchangeStore.digest(),
            conflictResolution: .useImported
        )
        let afterPeriodImport = try await subscriptionStore.fetchDetail(for: input.id)
        #expect(afterPeriodImport.periods.count == original.periods.count + 1)
        #expect(afterPeriodImport.subscription.revision == original.subscription.revision + 1)

        let payment = DataPackagePayment(
            recordVersion: 1,
            id: UUID(),
            subscriptionID: input.id,
            periodRecordID: extraPeriod.id,
            kind: .manual,
            paymentDate: .today,
            amountMinor: 999,
            currency: .usd,
            currencyScale: 2,
            periodStart: extraPeriod.start,
            periodEnd: extraPeriod.end,
            note: "Imported payment",
            attachmentAssetIDs: [],
            revision: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        imported.payments.append(payment)
        _ = try await exchangeStore.execute(
            imported: imported,
            expectedDigest: try await exchangeStore.digest(),
            conflictResolution: .useImported
        )
        let afterPaymentImport = try await subscriptionStore.fetchDetail(for: input.id)
        #expect(afterPaymentImport.payments.count == 1)
        #expect(afterPaymentImport.subscription.revision == afterPeriodImport.subscription.revision + 1)

        let repeated = try await exchangeStore.execute(
            imported: imported,
            expectedDigest: try await exchangeStore.digest(),
            conflictResolution: .useImported
        )
        #expect(repeated.added == 0)
        #expect(repeated.updated == 0)
        #expect(try await subscriptionStore.fetchDetail(for: input.id)
            .subscription.revision == afterPaymentImport.subscription.revision)

        imported.payments = [DataPackagePayment(
            recordVersion: payment.recordVersion,
            id: payment.id,
            subscriptionID: payment.subscriptionID,
            periodRecordID: payment.periodRecordID,
            kind: payment.kind,
            paymentDate: payment.paymentDate,
            amountMinor: 799,
            currency: payment.currency,
            currencyScale: payment.currencyScale,
            periodStart: payment.periodStart,
            periodEnd: payment.periodEnd,
            note: payment.note,
            attachmentAssetIDs: [],
            revision: payment.revision,
            createdAt: payment.createdAt,
            updatedAt: payment.updatedAt
        )]
        _ = try await exchangeStore.execute(
            imported: imported,
            expectedDigest: try await exchangeStore.digest(),
            conflictResolution: .keepLocal
        )
        #expect(try await subscriptionStore.fetchDetail(for: input.id)
            .subscription.revision == afterPaymentImport.subscription.revision)
        _ = try await exchangeStore.execute(
            imported: imported,
            expectedDigest: try await exchangeStore.digest(),
            conflictResolution: .useImported
        )
        let afterPaymentUpdate = try await subscriptionStore.fetchDetail(for: input.id)
        #expect(afterPaymentUpdate.payments.first?.money.minorUnits == 799)
        #expect(afterPaymentUpdate.subscription.revision == afterPaymentImport.subscription.revision + 1)
    }

    @MainActor
    @Test func importingCurrentFieldsAndHistoryAdvancesOwnerRevisionOnce() async throws {
        let sourceContainer = try makeContainer()
        let targetContainer = try makeContainer()
        let sourceStore = SubscriptionStore(modelContainer: sourceContainer)
        let targetStore = SubscriptionStore(modelContainer: targetContainer)
        let input = makeSubscriptionInput()
        _ = try await sourceStore.create(input)
        let exchangeStore = DataExchangeStore(modelContainer: targetContainer)
        let original = try await DataExchangeStore(modelContainer: sourceContainer).snapshot()
        _ = try await exchangeStore.execute(
            imported: original,
            expectedDigest: try await exchangeStore.digest(),
            conflictResolution: .keepLocal
        )
        try await sourceStore.setManagementState(
            .inactive,
            for: [SubscriptionMutationTarget(id: input.id, expectedRevision: 1)]
        )
        try await sourceStore.addPeriod(SubscriptionPeriodAddInput(
            period: SubscriptionPeriodCreateInput(
                id: UUID(),
                subscriptionID: input.id,
                billingKind: .recurring,
                cycleMonths: 1,
                start: LocalDate(dayNumber: 20_030),
                end: LocalDate(dayNumber: 20_059),
                money: input.money,
                source: .manual
            ),
            expectedSubscriptionRevision: 2
        ))
        let imported = try await DataExchangeStore(modelContainer: sourceContainer).snapshot()
        _ = try await exchangeStore.execute(
            imported: imported,
            expectedDigest: try await exchangeStore.digest(),
            conflictResolution: .useImported
        )
        let detail = try await targetStore.fetchDetail(for: input.id)
        #expect(detail.subscription.managementState == .inactive)
        #expect(detail.subscription.revision == 2)
        #expect(detail.periods.count == 2)
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
            iconCache: AppleIconCache(storageRoot: storageRoot),
            paymentAttachmentStore: PaymentAttachmentStore(storageRoot: storageRoot)
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

    private func makeSnapshot(
        reminderAdvanceDays: [Int]? = [7, 3, 1, 0],
        reminderMinuteOfDay: Int? = 9 * 60
    ) -> DataPackageSnapshot {
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
                    reminderAdvanceDays: reminderAdvanceDays,
                    reminderMinuteOfDay: reminderMinuteOfDay,
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
            payments: [
                DataPackagePayment(
                    recordVersion: 1,
                    id: UUID(),
                    subscriptionID: subscriptionID,
                    periodRecordID: periodID,
                    kind: .initial,
                    paymentDate: LocalDate(dayNumber: 20_000),
                    amountMinor: 1_499,
                    currency: .usd,
                    currencyScale: 2,
                    periodStart: LocalDate(dayNumber: 20_000),
                    periodEnd: LocalDate(dayNumber: 20_029),
                    note: "优惠支付",
                    attachmentAssetIDs: [],
                    revision: 1,
                    createdAt: timestamp,
                    updatedAt: timestamp
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
                SubscriptionSharingRecord.self,
                SubscriptionRecord.self,
                SubscriptionPeriodRecord.self,
                SubscriptionPaymentRecord.self,
                SubscriptionPaymentAttachmentRecord.self,
                SubscriptionPaymentAttachmentItemRecord.self,
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
