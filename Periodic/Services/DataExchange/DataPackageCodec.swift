import CryptoKit
import Foundation

enum DataPackageCodec {
    static let maximumPackageSize = 100 * 1_024 * 1_024
    private static let maximumRecordCount = 100_000
    private static let knownFiles: Set<String> = [
        "manifest.json",
        "checksums.json",
        "data/subscriptions.jsonl",
        "data/periods.jsonl",
        "data/templates.jsonl",
        "data/categories.jsonl",
        "data/builtin-category-assignments.jsonl",
        "data/settings.json",
    ]

    static func encode(
        snapshot: DataPackageSnapshot,
        assets: [String: Data],
        sourceDatasetID: UUID = UUID(),
        now: Date = .now
    ) throws -> EncodedDataPackage {
        try validate(snapshot)
        try validateAssetClosure(snapshot: snapshot, assetIdentifiers: Set(assets.keys))
        let manifest = DataPackageManifest(
            format: DataPackageManifest.currentFormat,
            formatVersion: DataPackageManifest.currentVersion,
            minimumReaderVersion: DataPackageManifest.currentVersion,
            exportID: UUID(),
            sourceDatasetID: sourceDatasetID,
            createdAt: now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            calendar: "gregorian",
            scope: "full",
            tables: .init(
                subscriptions: snapshot.subscriptions.count,
                periods: snapshot.periods.count,
                templates: snapshot.templates.count,
                categories: snapshot.categories.count,
                builtinCategoryAssignments: snapshot.builtinCategoryAssignments.count
            ),
            assetCount: assets.count,
            includesSettings: snapshot.settings != nil
        )
        var files: [String: Data] = [
            "manifest.json": try jsonEncoder().encode(manifest),
            "data/subscriptions.jsonl": try encodeLines(snapshot.subscriptions),
            "data/periods.jsonl": try encodeLines(snapshot.periods),
            "data/templates.jsonl": try encodeLines(snapshot.templates),
            "data/categories.jsonl": try encodeLines(snapshot.categories),
            "data/builtin-category-assignments.jsonl": try encodeLines(snapshot.builtinCategoryAssignments),
        ]
        if let settings = snapshot.settings {
            files["data/settings.json"] = try jsonEncoder().encode(settings)
        }
        for (identifier, data) in assets {
            guard identifier.count == 64, identifier.allSatisfy(\.isHexDigit) else {
                throw DataExchangeError.invalidPackage("图片标识无效")
            }
            files["assets/\(identifier).\(try imageExtension(data))"] = data
        }
        let checksums = Dictionary(uniqueKeysWithValues: files.map { ($0.key, sha256($0.value)) })
        files["checksums.json"] = try jsonEncoder().encode(checksums)
        guard files.values.reduce(0, { $0 + $1.count }) <= maximumPackageSize else {
            throw DataExchangeError.resourceLimitExceeded
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "Periodic Backup \(formatter.string(from: now)).periodicdata"
        return EncodedDataPackage(files: files, preferredFilename: filename)
    }

    static func decode(fileWrapper: FileWrapper) throws -> DecodedDataPackage {
        let files = try flattenedFiles(from: fileWrapper)
        guard files.values.reduce(0, { $0 + $1.count }) <= maximumPackageSize else {
            throw DataExchangeError.resourceLimitExceeded
        }
        guard let checksumData = files["checksums.json"] else {
            throw DataExchangeError.invalidPackage("缺少 checksums.json")
        }
        let checksums = try jsonDecoder().decode([String: String].self, from: checksumData)
        for (path, expected) in checksums {
            guard let data = files[path], sha256(data) == expected else {
                throw DataExchangeError.checksumMismatch(path)
            }
        }
        let declaredPaths = Set(checksums.keys).union(["checksums.json"])
        guard declaredPaths == Set(files.keys) else {
            throw DataExchangeError.invalidPackage("包含未声明文件或校验记录不完整")
        }
        guard let manifestData = files["manifest.json"] else {
            throw DataExchangeError.invalidPackage("缺少 manifest.json")
        }
        let manifest = try jsonDecoder().decode(DataPackageManifest.self, from: manifestData)
        guard manifest.format == DataPackageManifest.currentFormat else {
            throw DataExchangeError.invalidPackage("格式标识无法识别")
        }
        guard manifest.calendar == "gregorian", manifest.scope == "full" else {
            throw DataExchangeError.invalidPackage("日历或导出范围无法识别")
        }
        guard manifest.minimumReaderVersion <= DataPackageManifest.currentVersion,
              manifest.formatVersion == DataPackageManifest.currentVersion else {
            throw DataExchangeError.unsupportedVersion(manifest.formatVersion)
        }

        let snapshot = DataPackageSnapshot(
            subscriptions: try decodeLines(files["data/subscriptions.jsonl"], as: DataPackageSubscription.self),
            periods: try decodeLines(files["data/periods.jsonl"], as: DataPackagePeriod.self),
            templates: try decodeLines(files["data/templates.jsonl"], as: DataPackageTemplate.self),
            categories: try decodeLines(files["data/categories.jsonl"], as: DataPackageCategory.self),
            builtinCategoryAssignments: try decodeLines(
                files["data/builtin-category-assignments.jsonl"],
                as: DataPackageBuiltinCategoryAssignment.self
            ),
            settings: try files["data/settings.json"].map {
                try jsonDecoder().decode(DataPackageSettings.self, from: $0)
            }
        )
        try validate(snapshot)
        guard manifest.includesSettings == (snapshot.settings != nil) else {
            throw DataExchangeError.invalidPackage("设置声明与数据不一致")
        }
        guard manifest.tables.subscriptions == snapshot.subscriptions.count,
              manifest.tables.periods == snapshot.periods.count,
              manifest.tables.templates == snapshot.templates.count,
              manifest.tables.categories == snapshot.categories.count,
              manifest.tables.builtinCategoryAssignments == snapshot.builtinCategoryAssignments.count else {
            throw DataExchangeError.invalidPackage("manifest 数量与数据不一致")
        }
        var assets: [String: Data] = [:]
        for (path, data) in files where path.hasPrefix("assets/") {
            let fileURL = URL(filePath: path)
            guard fileURL.pathExtension == "png" || fileURL.pathExtension == "jpg" else {
                throw DataExchangeError.invalidPackage("图片扩展名无效")
            }
            let filename = fileURL.deletingPathExtension().lastPathComponent
            guard filename.count == 64,
                  filename.allSatisfy(\.isHexDigit),
                  sha256(data) == filename,
                  try imageExtension(data) == fileURL.pathExtension else {
                throw DataExchangeError.invalidPackage("图片内容校验失败")
            }
            assets[filename] = data
        }
        guard assets.count == manifest.assetCount else {
            throw DataExchangeError.invalidPackage("图片数量与 manifest 不一致")
        }
        try validateAssetClosure(snapshot: snapshot, assetIdentifiers: Set(assets.keys))
        return DecodedDataPackage(
            manifest: manifest,
            snapshot: snapshot,
            assets: assets,
            sourceDigest: sha256(checksumData)
        )
    }

    static func canonicalSnapshotData(_ snapshot: DataPackageSnapshot) throws -> Data {
        try jsonEncoder().encode(snapshot)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fileWrapper(for package: EncodedDataPackage) throws -> FileWrapper {
        let root = FileWrapper(directoryWithFileWrappers: [:])
        root.preferredFilename = package.preferredFilename
        for (path, data) in package.files.sorted(by: { $0.key < $1.key }) {
            try add(data: data, at: path, to: root)
        }
        return root
    }

    static func encodedPackage(from fileWrapper: FileWrapper) throws -> EncodedDataPackage {
        EncodedDataPackage(
            files: try flattenedFiles(from: fileWrapper),
            preferredFilename: fileWrapper.preferredFilename ?? "Periodic Backup.periodicdata"
        )
    }

    private static func validate(_ snapshot: DataPackageSnapshot) throws {
        let total = snapshot.subscriptions.count + snapshot.periods.count
            + snapshot.templates.count + snapshot.categories.count
            + snapshot.builtinCategoryAssignments.count
        guard total <= maximumRecordCount else { throw DataExchangeError.resourceLimitExceeded }
        try requireUnique(snapshot.subscriptions.map(\.id), table: "subscriptions")
        try requireUnique(snapshot.periods.map(\.id), table: "periods")
        try requireUnique(snapshot.templates.map(\.id), table: "templates")
        try requireUnique(snapshot.categories.map(\.id), table: "categories")
        try requireUnique(snapshot.builtinCategoryAssignments.map(\.templateKey), table: "assignments")

        let subscriptionIDs = Set(snapshot.subscriptions.map(\.id))
        guard snapshot.periods.allSatisfy({ subscriptionIDs.contains($0.subscriptionID) }) else {
            throw DataExchangeError.invalidRecord("周期缺少包内父订阅")
        }
        let categoryIDs = Set(snapshot.categories.map(\.id))
        guard snapshot.templates.compactMap(\.customCategoryID).allSatisfy(categoryIDs.contains),
              snapshot.builtinCategoryAssignments.compactMap(\.customCategoryID).allSatisfy(categoryIDs.contains) else {
            throw DataExchangeError.invalidRecord("模板引用了包外自定义分类")
        }
        for value in snapshot.subscriptions {
            guard value.recordVersion == 1,
                  value.currency.scale == value.currencyScale,
                  value.amountMinor >= 0,
                  !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DataExchangeError.invalidRecord("订阅金额或版本无效")
            }
            switch value.billingKind {
            case .recurring:
                guard let months = value.cycleMonths, BillingCycle(rawValue: months) != nil else {
                    throw DataExchangeError.invalidRecord("周期订阅缺少有效周期")
                }
            case .lifetime:
                guard value.expiry == nil, value.cycleMonths == nil,
                      !value.reminderEnabled, !value.automaticallyRenews else {
                    throw DataExchangeError.invalidRecord("终生订阅字段组合无效")
                }
            }
            if value.automaticallyRenews {
                guard value.managementState == .active,
                      value.billingKind == .recurring,
                      value.expiry != nil,
                      (value.cycleMonths ?? 0) > 0 else {
                    throw DataExchangeError.invalidRecord("自动续费字段组合无效")
                }
            }
        }
        for value in snapshot.periods {
            guard value.recordVersion == 1,
                  value.currency.scale == value.currencyScale,
                  value.amountMinor >= 0,
                  value.end.map({ value.start <= $0 }) ?? false else {
                throw DataExchangeError.invalidRecord("周期历史的金额、日期或版本无效")
            }
            switch value.billingKind {
            case .recurring:
                guard let months = value.cycleMonths, BillingCycle(rawValue: months) != nil else {
                    throw DataExchangeError.invalidRecord("周期历史缺少有效周期")
                }
            case .lifetime:
                guard value.cycleMonths == nil else {
                    throw DataExchangeError.invalidRecord("终生历史包含周期月数")
                }
            }
        }
        guard snapshot.templates.allSatisfy({
            $0.recordVersion == 1
                && $0.currency.scale == $0.currencyScale
                && ($0.suggestedAmountMinor ?? 0) >= 0
                && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (($0.suggestedBillingKind == .recurring
                    && $0.suggestedCycleMonths.flatMap(BillingCycle.init(rawValue:)) != nil)
                    || ($0.suggestedBillingKind == .lifetime
                        && $0.suggestedCycleMonths == nil))
        }), snapshot.categories.allSatisfy({
            $0.recordVersion == 1
                && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }),
        snapshot.builtinCategoryAssignments.allSatisfy({ $0.recordVersion == 1 }) else {
            throw DataExchangeError.invalidRecord("记录版本或货币元数据无效")
        }
        if let settings = snapshot.settings {
            try validate(settings)
        }
    }

    private static func validate(_ settings: DataPackageSettings) throws {
        guard settings.appearance.map({ AppAppearance(rawValue: $0) != nil }) ?? true,
              settings.language.map({ AppLanguage(rawValue: $0) != nil }) ?? true,
              settings.defaultCurrency.map({ CurrencyCode(rawValue: $0) != nil }) ?? true,
              settings.exchangeRateBaseCurrency.map({ CurrencyCode(rawValue: $0) != nil }) ?? true,
              DueHorizon(rawValue: settings.menuBarDueHorizon) != nil else {
            throw DataExchangeError.invalidRecord("设置包含无法识别的值")
        }
        if let storedValue = settings.selectedCurrencies, !storedValue.isEmpty {
            let selectedCurrencyValues = storedValue
                .split(separator: ",", omittingEmptySubsequences: false)
                .map(String.init)
            guard selectedCurrencyValues.allSatisfy({ CurrencyCode(rawValue: $0) != nil }),
                  Set(selectedCurrencyValues).count == selectedCurrencyValues.count else {
                throw DataExchangeError.invalidRecord("常用货币设置无效")
            }
        }
    }

    private static func validateAssetClosure(
        snapshot: DataPackageSnapshot,
        assetIdentifiers: Set<String>
    ) throws {
        let referencedAssets = Set(snapshot.subscriptions.compactMap(\.iconAssetID))
            .union(snapshot.templates.compactMap(\.iconAssetID))
        guard referencedAssets == assetIdentifiers else {
            throw DataExchangeError.invalidPackage("图片文件与记录引用不一致")
        }
    }

    private static func requireUnique<T: Hashable>(_ values: [T], table: String) throws {
        guard Set(values).count == values.count else {
            throw DataExchangeError.invalidRecord(String(
                format: AppLocalization.string("%@ 包含重复主键"),
                table
            ))
        }
    }

    private static func imageExtension(_ data: Data) throws -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        throw DataExchangeError.invalidPackage("图片不是 PNG 或 JPEG")
    }

    private static func encodeLines<T: Encodable>(_ values: [T]) throws -> Data {
        var result = Data()
        let encoder = jsonEncoder()
        for value in values {
            result.append(try encoder.encode(value))
            result.append(0x0A)
        }
        return result
    }

    private static func decodeLines<T: Decodable>(_ data: Data?, as type: T.Type) throws -> [T] {
        guard let data else { return [] }
        var values: [T] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            values.append(try jsonDecoder().decode(T.self, from: Data(line)))
        }
        return values
    }

    private static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func add(data: Data, at path: String, to root: FileWrapper) throws {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DataExchangeError.invalidPackage("文件路径无效")
        }
        var directory = root
        for component in components.dropLast() {
            if let existing = directory.fileWrappers?[component] {
                guard existing.isDirectory else {
                    throw DataExchangeError.invalidPackage("目录结构冲突")
                }
                directory = existing
            } else {
                let child = FileWrapper(directoryWithFileWrappers: [:])
                child.preferredFilename = component
                directory.addFileWrapper(child)
                directory = child
            }
        }
        let file = FileWrapper(regularFileWithContents: data)
        file.preferredFilename = components.last
        directory.addFileWrapper(file)
    }

    private static func flattenedFiles(from root: FileWrapper) throws -> [String: Data] {
        guard root.isDirectory else {
            throw DataExchangeError.invalidPackage("数据包必须是目录 package")
        }
        var result: [String: Data] = [:]
        try flatten(root, prefix: "", into: &result)
        return result
    }

    private static func flatten(
        _ wrapper: FileWrapper,
        prefix: String,
        into result: inout [String: Data]
    ) throws {
        guard !wrapper.isSymbolicLink else {
            throw DataExchangeError.invalidPackage("不允许符号链接")
        }
        guard let children = wrapper.fileWrappers else { return }
        for (name, child) in children {
            guard !name.hasPrefix("."), name != "..", !name.contains("/") else {
                throw DataExchangeError.invalidPackage("包含不安全路径")
            }
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            if child.isDirectory {
                guard path == "data" || path == "assets" else {
                    throw DataExchangeError.invalidPackage("包含未知目录")
                }
                try flatten(child, prefix: path, into: &result)
            } else if child.isRegularFile {
                guard knownFiles.contains(path) || path.hasPrefix("assets/") else {
                    throw DataExchangeError.invalidPackage(String(
                        format: AppLocalization.string("包含未知文件 %@"),
                        path
                    ))
                }
                guard let data = child.regularFileContents else {
                    throw DataExchangeError.invalidPackage(String(
                        format: AppLocalization.string("无法读取 %@"),
                        path
                    ))
                }
                result[path] = data
            } else {
                throw DataExchangeError.invalidPackage("包含不支持的文件类型")
            }
        }
    }
}
