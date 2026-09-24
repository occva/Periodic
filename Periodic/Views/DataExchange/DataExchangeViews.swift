import SwiftUI

struct DataExportPreviewView: View {
    let preview: DataExportPreview
    let isPreparing: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("完整备份", systemImage: "externaldrive.badge.timemachine")
                .font(.title2.weight(.semibold))
            Text("将创建一个 .periodicdata 数据包，包含当前全部订阅历史、用户模板、分类、设置和本地图标。")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                summaryRow("订阅", value: preview.subscriptions)
                summaryRow("周期历史", value: preview.periods)
                summaryRow("用户模板", value: preview.templates)
                summaryRow("自定义分类", value: preview.categories)
                summaryRow("分类覆盖", value: preview.assignments)
            }
            Text("备份未加密，可能包含订阅名称、金额、日期和备注，请妥善保管。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("选择保存位置…", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparing)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func summaryRow(_ title: String, value: Int) -> some View {
        GridRow {
            Text(AppLocalization.string(title)).foregroundStyle(.secondary)
            Text(String(format: AppLocalization.string("%d 项"), value)).monospacedDigit()
        }
    }
}

struct DataImportPreviewView: View {
    let plan: DataImportPlan
    @Binding var conflictResolution: DataImportConflictResolution
    @Binding var importsSettings: Bool
    let isImporting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("导入预览", systemImage: "square.and.arrow.down")
                .font(.title2.weight(.semibold))
            Text(String(
                format: AppLocalization.string("来源：Periodic 数据包 V%d，创建于 %@"),
                plan.package.manifest.formatVersion,
                plan.package.manifest.createdAt.formatted()
            ))
                .foregroundStyle(.secondary)
            Table(rows) {
                TableColumn("数据") { Text($0.name) }
                TableColumn("新增") { Text("\($0.changes.additions)").monospacedDigit() }
                TableColumn("冲突") { Text("\($0.changes.conflicts)").monospacedDigit() }
                TableColumn("相同") { Text("\($0.changes.unchanged)").monospacedDigit() }
            }
            .frame(height: 190)

            if plan.preview.totalConflicts > 0 {
                Picker("UUID 冲突处理", selection: $conflictResolution) {
                    ForEach(DataImportConflictResolution.allCases) { resolution in
                        Text(resolution.title).tag(resolution)
                    }
                }
                Text("名称相同但 UUID 不同的记录仍会作为新记录导入，不会按名称自动合并。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if plan.preview.assetCount > 0 {
                Text(String(
                    format: AppLocalization.string("同时验证并导入 %d 个本地图标。"),
                    plan.preview.assetCount
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if plan.package.manifest.includesSettings {
                Toggle("同时导入显示与菜单栏设置", isOn: $importsSettings)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("确认导入", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(isImporting)
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private var rows: [ImportPreviewRow] {
        [
            .init(name: AppLocalization.string("订阅"), changes: plan.preview.subscriptions),
            .init(name: AppLocalization.string("周期历史"), changes: plan.preview.periods),
            .init(name: AppLocalization.string("用户模板"), changes: plan.preview.templates),
            .init(name: AppLocalization.string("自定义分类"), changes: plan.preview.categories),
            .init(name: AppLocalization.string("分类覆盖"), changes: plan.preview.assignments),
        ]
    }
}

private struct ImportPreviewRow: Identifiable {
    let name: String
    let changes: DataImportPreview.EntityChanges
    var id: String { name }
}

struct DataExchangePresentationModifier: ViewModifier {
    @Bindable var feature: DataExchangeFeature
    let services: AppServices
    let onImported: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $feature.isPresentingImporter,
                allowedContentTypes: [.periodicDataPackage],
                allowsMultipleSelection: false
            ) { result in
                feature.inspect(result, using: services.dataExchange)
            }
            .fileExporter(
                isPresented: $feature.isPresentingExporter,
                document: feature.exportDocument,
                contentType: .periodicDataPackage,
                defaultFilename: feature.exportDocument?.package.preferredFilename
                    ?? "Periodic Backup.periodicdata"
            ) { result in
                feature.finishExport(result)
            }
            .sheet(isPresented: $feature.isPresentingExportPreview) {
                if let preview = feature.exportPreview {
                    DataExportPreviewView(
                        preview: preview,
                        isPreparing: feature.isBusy,
                        onCancel: { feature.isPresentingExportPreview = false },
                        onConfirm: { feature.confirmExport(using: services.dataExchange) }
                    )
                }
            }
            .sheet(isPresented: $feature.isPresentingImportPreview) {
                if let plan = feature.importPlan {
                    DataImportPreviewView(
                        plan: plan,
                        conflictResolution: $feature.conflictResolution,
                        importsSettings: $feature.importsSettings,
                        isImporting: feature.isBusy,
                        onCancel: { feature.isPresentingImportPreview = false },
                        onConfirm: {
                            feature.confirmImport(
                                using: services.dataExchange,
                                onImported: onImported
                            )
                        }
                    )
                }
            }
            .alert("数据操作完成", isPresented: $feature.isPresentingReceipt) {
                Button("好") { feature.dismissReceipt() }
            } message: {
                if case .completed(let message) = feature.phase {
                    Text(message)
                }
            }
            .errorAlert($feature.error)
    }
}

extension View {
    func dataExchangePresentation(
        feature: DataExchangeFeature,
        services: AppServices,
        onImported: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(
            DataExchangePresentationModifier(
                feature: feature,
                services: services,
                onImported: onImported
            )
        )
    }
}
