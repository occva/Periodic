import Foundation

actor DataExchangeService {
    private let store: DataExchangeStore
    private let iconCache: AppleIconCache
    private let paymentAttachmentStore: PaymentAttachmentStore

    init(
        store: DataExchangeStore,
        iconCache: AppleIconCache,
        paymentAttachmentStore: PaymentAttachmentStore
    ) {
        self.store = store
        self.iconCache = iconCache
        self.paymentAttachmentStore = paymentAttachmentStore
    }

    func previewExport() async throws -> DataExportPreview {
        let snapshot = try await store.snapshot()
        return DataExportPreview(
            subscriptions: snapshot.subscriptions.count,
            periods: snapshot.periods.count,
            payments: snapshot.payments.count,
            templates: snapshot.templates.count,
            categories: snapshot.categories.count,
            assignments: snapshot.builtinCategoryAssignments.count
        )
    }

    func referencedIconReferences() async throws -> Set<String> {
        try await store.referencedIconReferences()
    }

    func prepareExport() async throws -> EncodedDataPackage {
        var snapshot = try await store.snapshot()
        snapshot.settings = settingsSnapshot()
        var assets: [String: Data] = [:]
        var referenceToAsset: [String: String] = [:]
        let references = Set(snapshot.subscriptions.compactMap(\.iconAssetID))
            .union(snapshot.templates.compactMap(\.iconAssetID))
        for reference in references.sorted() {
            let data = try await iconCache.data(for: reference)
            let identifier = DataPackageCodec.sha256(data)
            assets[identifier] = data
            referenceToAsset[reference] = identifier
        }
        snapshot.subscriptions = snapshot.subscriptions.map { value in
            var copy = value
            copy.iconAssetID = value.iconAssetID.flatMap { referenceToAsset[$0] }
            return copy
        }
        snapshot.templates = snapshot.templates.map { value in
            var copy = value
            copy.iconAssetID = value.iconAssetID.flatMap { referenceToAsset[$0] }
            return copy
        }
        var attachmentReferenceToAsset: [String: String] = [:]
        let attachmentReferences = Set(snapshot.payments.flatMap(\.attachmentAssetIDs))
        for reference in attachmentReferences.sorted() {
            let data = try await paymentAttachmentStore.data(for: reference)
            let identifier = DataPackageCodec.sha256(data)
            assets[identifier] = data
            attachmentReferenceToAsset[reference] = identifier
        }
        snapshot.payments = snapshot.payments.map { value in
            var copy = value
            copy.attachmentAssetIDs = value.attachmentAssetIDs.map {
                attachmentReferenceToAsset[$0] ?? $0
            }
            return copy
        }
        return try DataPackageCodec.encode(
            snapshot: snapshot,
            assets: assets,
            sourceDatasetID: AppPreferenceValues.datasetID
        )
    }

    func inspect(url: URL) async throws -> DataImportPlan {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw DataExchangeError.invalidPackage("请选择 .periodicdata 数据包")
        }
        try preflightPackage(at: url)
        let wrapper = try FileWrapper(url: url, options: [.immediate])
        let package = try DataPackageCodec.decode(fileWrapper: wrapper)
        for data in package.assets.values {
            try await iconCache.validateImportedImage(data)
        }
        let targetDigest = try await store.digest()
        let comparisonSnapshot = try await snapshotResolvingKnownAssets(package)
        let basePreview = try await store.preview(imported: comparisonSnapshot)
        let preview = DataImportPreview(
            subscriptions: basePreview.subscriptions,
            periods: basePreview.periods,
            payments: basePreview.payments,
            templates: basePreview.templates,
            categories: basePreview.categories,
            assignments: basePreview.assignments,
            assetCount: package.assets.count
        )
        return DataImportPlan(
            id: UUID(),
            package: package,
            targetDigest: targetDigest,
            preview: preview,
            expiresAt: Date().addingTimeInterval(15 * 60)
        )
    }

    private func snapshotResolvingKnownAssets(
        _ package: DecodedDataPackage
    ) async throws -> DataPackageSnapshot {
        let local = try await store.snapshot()
        let references = Set(local.subscriptions.compactMap(\.iconAssetID))
            .union(local.templates.compactMap(\.iconAssetID))
        var assetToReference: [String: String] = [:]
        for reference in references {
            let data = try await iconCache.data(for: reference)
            assetToReference[DataPackageCodec.sha256(data)] = reference
        }
        var snapshot = package.snapshot
        snapshot.subscriptions = snapshot.subscriptions.map { value in
            var copy = value
            copy.iconAssetID = value.iconAssetID.flatMap { assetToReference[$0] ?? $0 }
            return copy
        }
        snapshot.templates = snapshot.templates.map { value in
            var copy = value
            copy.iconAssetID = value.iconAssetID.flatMap { assetToReference[$0] ?? $0 }
            return copy
        }
        var attachmentAssetToReference: [String: String] = [:]
        for reference in Set(local.payments.flatMap(\.attachmentAssetIDs)) {
            let data = try await paymentAttachmentStore.data(for: reference)
            attachmentAssetToReference[DataPackageCodec.sha256(data)] = reference
        }
        snapshot.payments = snapshot.payments.map { value in
            var copy = value
            copy.attachmentAssetIDs = value.attachmentAssetIDs.map {
                attachmentAssetToReference[$0] ?? $0
            }
            return copy
        }
        return snapshot
    }

    func execute(
        plan: DataImportPlan,
        conflictResolution: DataImportConflictResolution,
        importsSettings: Bool
    ) async throws -> DataImportReceipt {
        guard plan.expiresAt > Date() else { throw DataExchangeError.planExpired }
        let iconAssetIdentifiers = Set(
            plan.package.snapshot.subscriptions.compactMap(\.iconAssetID)
        ).union(plan.package.snapshot.templates.compactMap(\.iconAssetID))
        let paymentAssetIdentifiers = Set(
            plan.package.snapshot.payments.flatMap(\.attachmentAssetIDs)
        )
        let previousPaymentAttachmentReferences = try await store
            .referencedPaymentAttachmentReferences()
        var iconWrites: [AppleIconCache.ImportedImageWrite] = []
        var paymentWrites: [PaymentAttachmentStore.ImportedImageWrite] = []
        var iconAssetReferences: [String: String] = [:]
        var paymentAssetReferences: [String: String] = [:]
        do {
            for identifier in iconAssetIdentifiers.sorted() {
                guard let data = plan.package.assets[identifier] else {
                    throw DataExchangeError.invalidPackage("图片引用缺少文件")
                }
                let write = try await iconCache.persistImportedImage(data)
                iconWrites.append(write)
                iconAssetReferences[identifier] = write.reference
            }
            for identifier in paymentAssetIdentifiers.sorted() {
                guard let data = plan.package.assets[identifier] else {
                    throw DataExchangeError.invalidPackage("消费截图引用缺少文件")
                }
                let write = try await paymentAttachmentStore.persistImportedImage(data)
                paymentWrites.append(write)
                paymentAssetReferences[identifier] = write.reference
            }
        } catch {
            await iconCache.discardImportedImages(iconWrites)
            await paymentAttachmentStore.discardImportedImages(
                paymentWrites,
                keeping: previousPaymentAttachmentReferences
            )
            throw error
        }

        var snapshot = plan.package.snapshot
        snapshot.subscriptions = snapshot.subscriptions.map { value in
            var copy = value
            copy.iconAssetID = value.iconAssetID.flatMap { iconAssetReferences[$0] }
            return copy
        }
        snapshot.templates = snapshot.templates.map { value in
            var copy = value
            copy.iconAssetID = value.iconAssetID.flatMap { iconAssetReferences[$0] }
            return copy
        }
        snapshot.payments = snapshot.payments.map { value in
            var copy = value
            copy.attachmentAssetIDs = value.attachmentAssetIDs.map {
                paymentAssetReferences[$0] ?? $0
            }
            return copy
        }

        let receipt: DataImportReceipt
        do {
            receipt = try await store.execute(
                imported: snapshot,
                expectedDigest: plan.targetDigest,
                conflictResolution: conflictResolution
            )
        } catch {
            await iconCache.discardImportedImages(iconWrites)
            await paymentAttachmentStore.discardImportedImages(
                paymentWrites,
                keeping: previousPaymentAttachmentReferences
            )
            throw error
        }

        do {
            let referencedImages = try await store.referencedIconReferences()
            await iconCache.discardImportedImages(iconWrites, keeping: referencedImages)
            let referencedPaymentAttachments = try await store
                .referencedPaymentAttachmentReferences()
            await paymentAttachmentStore.releaseImportedImages(paymentWrites)
            _ = await paymentAttachmentStore.removeStoredImages(
                references: previousPaymentAttachmentReferences.subtracting(
                    referencedPaymentAttachments
                )
            )
        } catch {
            // The database transaction has committed. Retain the files rather
            // than deleting assets that may now be referenced by imported rows.
            await paymentAttachmentStore.releaseImportedImages(paymentWrites)
            AppLog.persistence.error("Failed to remove unreferenced imported icons")
        }
        if importsSettings, let settings = snapshot.settings {
            apply(settings)
        }
        return receipt
    }

    private func settingsSnapshot() -> DataPackageSettings {
        let defaults = UserDefaults.standard
        let selectedCurrencies = CurrencyPreferences.storedValue(
            for: CurrencyPreferences.selectedCurrencies(
                from: defaults.string(forKey: PreferenceKey.selectedCurrencies) ?? ""
            )
        )
        return DataPackageSettings(
            appearance: (defaults.string(forKey: PreferenceKey.appearance)
                .flatMap(AppAppearance.init(rawValue:)) ?? .system).rawValue,
            language: (defaults.string(forKey: PreferenceKey.language)
                .flatMap(AppLanguage.init(rawValue:)) ?? .system).rawValue,
            defaultCurrency: AppPreferenceValues.defaultCurrency.rawValue,
            selectedCurrencies: selectedCurrencies,
            usesCurrencySymbols: defaults.bool(forKey: PreferenceKey.usesCurrencySymbols),
            menuBarEnabled: defaults.object(forKey: PreferenceKey.menuBarEnabled) as? Bool ?? true,
            menuBarDueHorizon: MenuBarPreferences.normalizedDueHorizonRawValue(
                defaults.object(forKey: PreferenceKey.menuBarDueHorizon) as? Int
                    ?? MenuBarPreferences.defaultDueHorizon.rawValue
            ),
            menuBarShowsForecasts: defaults.object(forKey: PreferenceKey.menuBarShowsForecasts) as? Bool ?? true,
            exchangeRateBaseCurrency: AppPreferenceValues.exchangeRateBaseCurrency.rawValue
        )
    }

    private func apply(_ settings: DataPackageSettings) {
        let defaults = UserDefaults.standard
        set(settings.appearance, forKey: PreferenceKey.appearance, defaults: defaults)
        set(settings.language, forKey: PreferenceKey.language, defaults: defaults)
        set(settings.defaultCurrency, forKey: PreferenceKey.defaultCurrency, defaults: defaults)
        set(settings.selectedCurrencies, forKey: PreferenceKey.selectedCurrencies, defaults: defaults)
        defaults.set(settings.usesCurrencySymbols, forKey: PreferenceKey.usesCurrencySymbols)
        defaults.set(settings.menuBarEnabled, forKey: PreferenceKey.menuBarEnabled)
        defaults.set(settings.menuBarDueHorizon, forKey: PreferenceKey.menuBarDueHorizon)
        defaults.set(settings.menuBarShowsForecasts, forKey: PreferenceKey.menuBarShowsForecasts)
        set(
            settings.exchangeRateBaseCurrency,
            forKey: PreferenceKey.exchangeRateBaseCurrency,
            defaults: defaults
        )
    }

    private func set(_ value: String?, forKey key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func preflightPackage(at url: URL) throws {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw DataExchangeError.invalidPackage("无法读取数据包目录")
        }
        var totalSize = 0
        var entryCount = 0
        for case let childURL as URL in enumerator {
            entryCount += 1
            guard entryCount <= 100_100 else {
                throw DataExchangeError.resourceLimitExceeded
            }
            let values = try childURL.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true else {
                throw DataExchangeError.invalidPackage("包含不支持的文件类型")
            }
            guard values.isRegularFile == true else { continue }
            let (nextSize, overflow) = totalSize.addingReportingOverflow(values.fileSize ?? 0)
            guard !overflow, nextSize <= DataPackageCodec.maximumPackageSize else {
                throw DataExchangeError.resourceLimitExceeded
            }
            totalSize = nextSize
        }
    }
}
