import SwiftUI

struct DataSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var feature = DataExchangeFeature()

    var body: some View {
        Form {
            Section("Periodic 数据包") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("备份与迁移", systemImage: "externaldrive")
                        .font(.headline)
                    Text("完整备份包含订阅与周期历史、用户模板、分类、设置和本地图标。导入前会先显示新增、冲突和跳过数量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("导入数据…") { feature.requestImport() }
                    Button("导出完整备份…") {
                        feature.requestExport(using: services.dataExchange)
                    }
                }
                .disabled(feature.isBusy)
            }

        }
        .formStyle(.grouped)
        .dataExchangePresentation(
            feature: feature,
            services: services,
            onImported: {
                services.notifySubscriptionDataChanged()
                services.notifyTemplateDataChanged()
            }
        )
    }
}
