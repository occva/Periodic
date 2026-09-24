import Foundation
import Observation

@MainActor
@Observable
final class DataExchangeFeature {
    enum Phase: Equatable {
        case idle
        case preparingExport
        case awaitingExportConfirmation
        case awaitingExportDestination
        case reading
        case awaitingImportConfirmation
        case importing
        case completed(String)
    }

    private(set) var phase = Phase.idle
    private(set) var exportPreview: DataExportPreview?
    private(set) var importPlan: DataImportPlan?
    private(set) var exportDocument: PeriodicDataPackageDocument?
    var conflictResolution = DataImportConflictResolution.keepLocal
    var importsSettings = true
    var isPresentingImporter = false
    var isPresentingExportPreview = false
    var isPresentingImportPreview = false
    var isPresentingExporter = false
    var isPresentingReceipt = false
    var error: PresentedError?

    var isBusy: Bool {
        switch phase {
        case .preparingExport, .reading, .importing: true
        default: false
        }
    }

    func requestExport(using service: DataExchangeService?) {
        guard let service else {
            error = PresentedError(DataExchangeError.storeUnavailable, title: "无法导出数据")
            return
        }
        phase = .preparingExport
        Task {
            do {
                exportPreview = try await service.previewExport()
                phase = .awaitingExportConfirmation
                isPresentingExportPreview = true
            } catch {
                fail(error, title: "无法准备导出")
            }
        }
    }

    func confirmExport(using service: DataExchangeService?) {
        guard let service else {
            error = PresentedError(DataExchangeError.storeUnavailable, title: "无法导出数据")
            return
        }
        isPresentingExportPreview = false
        phase = .preparingExport
        Task {
            do {
                let package = try await service.prepareExport()
                exportDocument = PeriodicDataPackageDocument(package: package)
                phase = .awaitingExportDestination
                isPresentingExporter = true
            } catch {
                fail(error, title: "无法导出数据")
            }
        }
    }

    func finishExport(_ result: Result<URL, Error>) {
        isPresentingExporter = false
        exportDocument = nil
        switch result {
        case .success:
            phase = .completed(AppLocalization.string("完整备份已导出。"))
            isPresentingReceipt = true
        case .failure(let error):
            if (error as NSError).code == NSUserCancelledError {
                phase = .idle
            } else {
                fail(error, title: "无法保存备份")
            }
        }
    }

    func requestImport() {
        guard !isBusy else { return }
        isPresentingImporter = true
    }

    func inspect(_ result: Result<[URL], Error>, using service: DataExchangeService?) {
        isPresentingImporter = false
        switch result {
        case .success(let urls):
            guard let url = urls.first, let service else {
                if service == nil {
                    error = PresentedError(DataExchangeError.storeUnavailable, title: "无法导入数据")
                }
                return
            }
            phase = .reading
            Task {
                do {
                    importPlan = try await service.inspect(url: url)
                    conflictResolution = .keepLocal
                    importsSettings = true
                    phase = .awaitingImportConfirmation
                    isPresentingImportPreview = true
                } catch {
                    fail(error, title: "无法读取数据包")
                }
            }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                fail(error, title: "无法选择数据包")
            }
        }
    }

    func confirmImport(
        using service: DataExchangeService?,
        onImported: @escaping @MainActor () async -> Void
    ) {
        guard let service, let importPlan else {
            error = PresentedError(DataExchangeError.storeUnavailable, title: "无法导入数据")
            return
        }
        isPresentingImportPreview = false
        phase = .importing
        Task {
            do {
                let receipt = try await service.execute(
                    plan: importPlan,
                    conflictResolution: conflictResolution,
                    importsSettings: importsSettings
                )
                self.importPlan = nil
                await onImported()
                phase = .completed(String(
                    format: AppLocalization.string("导入完成：新增 %d，更新 %d，跳过 %d。"),
                    receipt.added,
                    receipt.updated,
                    receipt.skipped
                ))
                isPresentingReceipt = true
            } catch {
                fail(error, title: "无法导入数据")
            }
        }
    }

    func dismissReceipt() {
        isPresentingReceipt = false
        phase = .idle
    }

    private func fail(_ error: Error, title: String) {
        self.error = PresentedError(error, title: title)
        phase = .idle
    }
}
