import SwiftUI

struct CloudSyncConflictView: View {
    @Bindable var coordinator: CloudSyncCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var resolvingConflictID: UUID?
    @State private var error: PresentedError?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            HStack {
                Spacer()
                Button(AppLocalization.string("关闭")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 460)
        .errorAlert($error)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.string("处理 iCloud 冲突"))
                    .font(.title2.weight(.semibold))
                Text(AppLocalization.string("选择要保留的版本后，Periodic 会继续同步其他记录。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if coordinator.snapshot.conflicts.isEmpty {
            ContentUnavailableView(
                AppLocalization.string("没有待处理冲突"),
                systemImage: "checkmark.icloud",
                description: Text(
                    AppLocalization.string("所有可同步记录都已完成合并。")
                )
            )
        } else {
            List(coordinator.snapshot.conflicts) { conflict in
                conflictRow(conflict)
                    .padding(.vertical, 8)
            }
            .listStyle(.inset)
        }
    }

    private func conflictRow(
        _ conflict: CloudSyncConflictSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflictTitle(conflict))
                        .font(.headline)
                    Text(recordTypeTitle(conflict.recordType))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(
                    conflict.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            if conflict.involvesDeletion {
                Label(
                    AppLocalization.string("一端已删除，另一端仍有修改。为避免旧数据自动复活，请先在业务页面复制需要保留的内容。"),
                    systemImage: "trash.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                conflictComparison(conflict)
                HStack {
                    Spacer()
                    Button(AppLocalization.string("保留此 Mac")) {
                        resolve(conflict, resolution: .keepLocal)
                    }
                    Button(AppLocalization.string("使用 iCloud")) {
                        resolve(conflict, resolution: .useRemote)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .disabled(
                    coordinator.isBusy
                        || resolvingConflictID != nil
                        || !conflict.canResolveDirectly
                )
            }
        }
    }

    private func conflictComparison(
        _ conflict: CloudSyncConflictSummary
    ) -> some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: 16,
            verticalSpacing: 6
        ) {
            GridRow {
                Text(AppLocalization.string("字段"))
                    .foregroundStyle(.secondary)
                Text(AppLocalization.string("此 Mac"))
                    .foregroundStyle(.secondary)
                Text("iCloud")
                    .foregroundStyle(.secondary)
            }
            Divider()
                .gridCellUnsizedAxes(.horizontal)
            ForEach(conflict.fieldNames, id: \.self) { field in
                GridRow {
                    Text(fieldTitle(field))
                    Text(valueText(conflict.localValues[field]))
                        .textSelection(.enabled)
                    Text(valueText(conflict.remoteValues[field]))
                        .textSelection(.enabled)
                }
            }
        }
        .font(.callout)
    }

    private func resolve(
        _ conflict: CloudSyncConflictSummary,
        resolution: CloudSyncConflictResolution
    ) {
        resolvingConflictID = conflict.id
        Task {
            do {
                try await coordinator.resolveConflict(
                    conflict.id,
                    resolution: resolution
                )
                resolvingConflictID = nil
            } catch {
                self.error = PresentedError(
                    error,
                    title: AppLocalization.string("无法处理同步冲突")
                )
                resolvingConflictID = nil
            }
        }
    }

    private func conflictTitle(
        _ conflict: CloudSyncConflictSummary
    ) -> String {
        for field in ["name", "note", "reference"] {
            if case .string(let value) = conflict.localValues[field],
               !value.isEmpty {
                return value
            }
            if case .string(let value) = conflict.remoteValues[field],
               !value.isEmpty {
                return value
            }
        }
        return conflict.recordID
    }

    private func recordTypeTitle(_ recordType: SyncRecordType) -> String {
        switch recordType {
        case .subscription:
            AppLocalization.string("订阅")
        case .subscriptionPeriod:
            AppLocalization.string("周期")
        case .subscriptionPayment:
            AppLocalization.string("付款")
        case .serviceTemplate:
            AppLocalization.string("用户模板")
        case .templateCategory:
            AppLocalization.string("自定义分类")
        case .builtinTemplateCategoryAssignment:
            AppLocalization.string("内置模板分类")
        case .iconAsset:
            AppLocalization.string("图片")
        }
    }

    private func fieldTitle(_ field: String) -> String {
        let titles = [
            "name": AppLocalization.string("名称"),
            "note": AppLocalization.string("备注"),
            "iconURLString": AppLocalization.string("图标"),
            "categoryRaw": AppLocalization.string("服务类型"),
            "managementStateRaw": AppLocalization.string("管理状态"),
            "billingKindRaw": AppLocalization.string("计费类型"),
            "periodStartDay": AppLocalization.string("开始日期"),
            "expiryDay": AppLocalization.string("到期日期"),
            "cycleMonths": AppLocalization.string("周期"),
            "periodAmountMinor": AppLocalization.string("金额"),
            "amountMinor": AppLocalization.string("金额"),
            "currencyCode": AppLocalization.string("币种"),
            "paymentDay": AppLocalization.string("付款日期"),
            "attachmentReferences": AppLocalization.string("附件"),
            "customCategoryID": AppLocalization.string("自定义分类"),
            "reference": AppLocalization.string("图片引用"),
            "contentHash": AppLocalization.string("图片校验值"),
        ]
        return titles[field] ?? field
    }

    private func valueText(_ value: SyncValue?) -> String {
        guard let value else {
            return AppLocalization.string("无")
        }
        switch value {
        case .null:
            return AppLocalization.string("无")
        case .bool(let value):
            return value
                ? AppLocalization.string("是")
                : AppLocalization.string("否")
        case .integer(let value):
            return value.formatted()
        case .string(let value):
            return value.isEmpty
                ? AppLocalization.string("空")
                : value
        case .date(let value):
            return value.formatted(date: .abbreviated, time: .shortened)
        case .data:
            return AppLocalization.string("二进制数据")
        case .array(let values):
            return values.map { valueText($0) }.joined(separator: "、")
        case .object:
            return AppLocalization.string("复合数据")
        }
    }
}
