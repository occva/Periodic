import AppKit
import SwiftUI

struct CloudSyncSettingsView: View {
    @Bindable var coordinator: CloudSyncCoordinator
    @State private var enablementPreview: CloudEnablementPreview?
    @State private var isShowingEnablement = false
    @State private var isShowingConflicts = false
    @State private var isShowingDisableConfirmation = false
    @State private var error: PresentedError?

    var body: some View {
        Form {
            Section(AppLocalization.string("iCloud 状态")) {
                LabeledContent(AppLocalization.string("同步")) {
                    Label(statusTitle, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                }

                if let message = coordinator.snapshot.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if coordinator.snapshot.isEnabled {
                enabledContent
            } else {
                disabledContent
            }

            if let safetySnapshotURL =
                coordinator.snapshot.lastSafetySnapshotURL {
                Section(AppLocalization.string("安全快照")) {
                    LabeledContent(AppLocalization.string("最近快照")) {
                        Text(safetySnapshotURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button(AppLocalization.string("在 Finder 中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            safetySnapshotURL,
                        ])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await coordinator.refreshStatus()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await coordinator.refreshStatus()
            }
        }
        .sheet(isPresented: $isShowingEnablement) {
            if let enablementPreview {
                CloudSyncEnablementView(
                    preview: enablementPreview,
                    isEnabling: coordinator.isBusy,
                    onCancel: {
                        isShowingEnablement = false
                    },
                    onEnable: enableSync
                )
            }
        }
        .sheet(isPresented: $isShowingConflicts) {
            CloudSyncConflictView(coordinator: coordinator)
        }
        .confirmationDialog(
            AppLocalization.string("停止 iCloud 同步？"),
            isPresented: $isShowingDisableConfirmation
        ) {
            Button(AppLocalization.string("停止同步并保留此 Mac 数据"), role: .destructive) {
                disableSync()
            }
            Button(AppLocalization.string("取消"), role: .cancel) {}
        } message: {
            Text(AppLocalization.string("此 Mac 的订阅与图片会继续保留。之后的本地修改会排队，重新启用同步时再合并到 iCloud。"))
        }
        .errorAlert($error)
    }

    private var disabledContent: some View {
        Section(AppLocalization.string("启用同步")) {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    AppLocalization.string("在你的 Apple ID 私有空间中同步"),
                    systemImage: "icloud"
                )
                .font(.headline)
                Text(AppLocalization.string("同步订阅、周期与消费历史、用户模板、分类以及本地图片。Periodic 不会创建独立账号，也不会把数据发送到自有服务器。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let summary = coordinator.snapshot.localSummary {
                summaryRows(summary)
            }

            Button(AppLocalization.string("检查并准备启用…")) {
                previewEnablement()
            }
            .disabled(coordinator.isBusy)
        }
    }

    private var enabledContent: some View {
        Group {
            Section(AppLocalization.string("同步进度")) {
                LabeledContent(
                    AppLocalization.string("待上传"),
                    value: "\(coordinator.snapshot.queue.pendingUploadCount)"
                )
                LabeledContent(
                    AppLocalization.string("待应用"),
                    value: "\(coordinator.snapshot.queue.pendingDownloadCount)"
                )
                LabeledContent(AppLocalization.string("冲突")) {
                    if coordinator.snapshot.queue.conflictCount > 0 {
                        Button(
                            String(
                                format: AppLocalization.string("%lld 项待处理…"),
                                Int64(
                                    coordinator.snapshot.queue.conflictCount
                                )
                            )
                        ) {
                            isShowingConflicts = true
                        }
                    } else {
                        Text("0")
                    }
                }
                LabeledContent(AppLocalization.string("最近成功")) {
                    if let date =
                        coordinator.snapshot.lastSuccessfulSyncAt {
                        Text(
                            date.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    } else {
                        Text(AppLocalization.string("尚未完成"))
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await coordinator.syncNow() }
                } label: {
                    Label(AppLocalization.string("立即同步"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(coordinator.isBusy)
            }

            if let summary = coordinator.snapshot.localSummary {
                Section(AppLocalization.string("此 Mac 数据")) {
                    summaryRows(summary)
                }
            }

            Section {
                Button(AppLocalization.string("停止 iCloud 同步…"), role: .destructive) {
                    isShowingDisableConfirmation = true
                }
                .disabled(coordinator.isBusy)
            } footer: {
                Text(AppLocalization.string("停止同步不会删除此 Mac 数据，也不会自动删除 iCloud 中已上传的数据。"))
            }
        }
    }

    @ViewBuilder
    private func summaryRows(_ summary: CloudSyncDataSummary) -> some View {
        LabeledContent(
            AppLocalization.string("订阅与历史"),
            value: "\(summary.subscriptions) / \(summary.periods) / \(summary.payments)"
        )
        LabeledContent(
            AppLocalization.string("模板与分类"),
            value: "\(summary.templates) / \(summary.categories)"
        )
        LabeledContent(
            AppLocalization.string("图片"),
            value: "\(summary.imageCount)"
        )
        LabeledContent(
            AppLocalization.string("图片大小"),
            value: ByteCountFormatter.string(
                fromByteCount: summary.estimatedBytes,
                countStyle: .file
            )
        )
    }

    private var statusTitle: String {
        switch coordinator.snapshot.phase {
        case .disabled: AppLocalization.string("未启用")
        case .checking: AppLocalization.string("正在检查")
        case .preparing: AppLocalization.string("正在准备")
        case .idle: AppLocalization.string("已同步")
        case .syncing: AppLocalization.string("正在同步")
        case .retrying: AppLocalization.string("等待重试")
        case .needsAccount: AppLocalization.string("需要登录 iCloud")
        case .accountChanged: AppLocalization.string("Apple ID 已变化")
        case .conflicted: AppLocalization.string("需要处理冲突")
        case .failed: AppLocalization.string("同步失败")
        }
    }

    private var statusDetail: String {
        switch coordinator.snapshot.phase {
        case .disabled:
            AppLocalization.string("默认关闭，不会访问 CloudKit。")
        case .checking:
            AppLocalization.string("正在检查 Apple ID、同步容器和本地数据。")
        case .preparing:
            AppLocalization.string("正在创建安全快照并建立首次同步队列。")
        case .idle:
            AppLocalization.string("此 Mac 已完成最近一次同步。")
        case .syncing:
            AppLocalization.string("本地浏览和编辑可以继续进行。")
        case .retrying:
            AppLocalization.string("网络或 iCloud 暂时不可用，恢复后会继续。")
        case .needsAccount:
            AppLocalization.string("请先在系统设置中登录可用的 Apple ID。")
        case .accountChanged:
            AppLocalization.string("为避免混合两个 Apple ID 的数据，同步已暂停。")
        case .conflicted:
            AppLocalization.string("存在无法安全自动合并的同字段修改。")
        case .failed:
            AppLocalization.string("本地数据保持不变，可以稍后重试。")
        }
    }

    private var statusSymbol: String {
        switch coordinator.snapshot.phase {
        case .disabled: "icloud.slash"
        case .checking, .preparing, .syncing: "icloud.and.arrow.up"
        case .idle: "checkmark.icloud"
        case .retrying: "arrow.clockwise.icloud"
        case .needsAccount, .accountChanged: "person.crop.circle.badge.exclamationmark"
        case .conflicted, .failed: "exclamationmark.icloud"
        }
    }

    private var statusColor: Color {
        switch coordinator.snapshot.phase {
        case .idle: .green
        case .retrying, .needsAccount, .accountChanged, .conflicted: .orange
        case .failed: .red
        default: .secondary
        }
    }

    private func previewEnablement() {
        Task {
            do {
                enablementPreview = try await coordinator
                    .previewEnablement()
                isShowingEnablement = true
            } catch {
                self.error = PresentedError(
                    error,
                    title: AppLocalization.string("无法准备 iCloud 同步")
                )
            }
        }
    }

    private func enableSync() {
        Task {
            do {
                try await coordinator.enable()
                isShowingEnablement = false
            } catch {
                self.error = PresentedError(
                    error,
                    title: AppLocalization.string("无法启用 iCloud 同步")
                )
            }
        }
    }

    private func disableSync() {
        Task {
            do {
                try await coordinator.disableKeepingLocalData()
            } catch {
                self.error = PresentedError(
                    error,
                    title: AppLocalization.string("无法停止 iCloud 同步")
                )
            }
        }
    }
}

private struct CloudSyncEnablementView: View {
    let preview: CloudEnablementPreview
    let isEnabling: Bool
    let onCancel: () -> Void
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(AppLocalization.string("启用 iCloud 同步"), systemImage: "icloud")
                .font(.title2.weight(.semibold))

            Text(preview.mergeDescription)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Color.clear
                        .frame(width: 1, height: 1)
                    Text(AppLocalization.string("此 Mac"))
                        .foregroundStyle(.secondary)
                    Text("iCloud")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text(AppLocalization.string("订阅"))
                    Text("\(preview.localSummary.subscriptions)")
                    Text("\(preview.remoteSummary.subscriptions)")
                }
                GridRow {
                    Text(AppLocalization.string("周期 / 付款"))
                    Text(
                        "\(preview.localSummary.periods) / \(preview.localSummary.payments)"
                    )
                    Text(
                        "\(preview.remoteSummary.periods) / \(preview.remoteSummary.payments)"
                    )
                }
                GridRow {
                    Text(AppLocalization.string("模板 / 分类"))
                    Text(
                        "\(preview.localSummary.templates) / \(preview.localSummary.categories)"
                    )
                    Text(
                        "\(preview.remoteSummary.templates) / \(preview.remoteSummary.categories)"
                    )
                }
                GridRow {
                    Text(AppLocalization.string("图片"))
                    Text(
                        "\(preview.localSummary.imageCount)，\(ByteCountFormatter.string(fromByteCount: preview.localSummary.estimatedBytes, countStyle: .file))"
                    )
                    Text(
                        "\(preview.remoteSummary.imageCount)，\(ByteCountFormatter.string(fromByteCount: preview.remoteSummary.estimatedBytes, countStyle: .file))"
                    )
                }
            }

            Label(
                AppLocalization.string("启用前会在此 Mac 创建完整 .periodicdata 安全快照。任何失败都不会删除当前数据库。"),
                systemImage: "externaldrive.badge.checkmark"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(AppLocalization.string("取消"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(AppLocalization.string("创建快照并启用"), action: onEnable)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isEnabling)
            }
        }
        .padding(24)
        .frame(width: 580)
    }
}
