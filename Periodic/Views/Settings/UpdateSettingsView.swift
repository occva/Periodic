import SwiftUI

struct UpdateSettingsView: View {
    @Environment(AppUpdateService.self) private var updates

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(verbatim: AppReleaseInfo.current.version)
                } label: {
                    Text("当前版本", tableName: "Updates")
                }
                Button(action: updates.checkForUpdates) {
                    Text("检查更新…", tableName: "Updates")
                }
                .disabled(!updates.canCheckForUpdates)

                if let error = updates.startupError {
                    Text(error.message)
                        .foregroundStyle(.secondary)
                } else if updates.availability != .available {
                    availabilityDescription
                        .foregroundStyle(.secondary)
                }

                if let date = updates.lastUpdateCheckDate {
                    LabeledContent {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                    } label: {
                        Text("上次检查", tableName: "Updates")
                    }
                }
            } header: {
                Text("版本与更新", tableName: "Updates")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: updates.setAutomaticallyChecksForUpdates
                )) {
                    Text("自动检查更新", tableName: "Updates")
                }
                Toggle(isOn: Binding(
                    get: { updates.automaticallyDownloadsUpdates },
                    set: updates.setAutomaticallyDownloadsUpdates
                )) {
                    Text("自动下载并安装更新", tableName: "Updates")
                }
                .disabled(!updates.automaticallyChecksForUpdates)
            } header: {
                Text("更新偏好", tableName: "Updates")
            }
            .disabled(updates.availability != .available || updates.startupError != nil)

            if updates.isWaitingToRestart {
                Section {
                    Text(
                        "更新等待重启。请保存或取消所有编辑、关闭对话框，并等待数据操作完成。",
                        tableName: "Updates"
                    )
                    Button(action: updates.resumePendingInstallation) {
                        Text("完成编辑并重启更新", tableName: "Updates")
                    }
                } header: {
                    Text("更新已准备好", tableName: "Updates")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var availabilityDescription: some View {
        switch updates.availability {
        case .available:
            EmptyView()
        case .developmentBuild:
            Text("开发构建和样本模式不检查或安装正式版更新。", tableName: "Updates")
        case .invalidConfiguration:
            Text("更新配置不完整，请从官方发布页重新下载完整安装包。", tableName: "Updates")
        }
    }
}
