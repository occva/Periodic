import SwiftUI

enum TimelineSpecialCollection: String, Identifiable {
    case undated
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .undated: AppLocalization.string("无日期订阅")
        case .lifetime: AppLocalization.string("终生项目")
        }
    }
}

struct TimelineCollectionListView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let items: [SubscriptionListItem]
    let onDetails: (UUID) -> Void
    let onEdit: (UUID) -> Void

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    onDetails(item.id)
                } label: {
                    HStack(spacing: 10) {
                        ServiceIconView(
                            iconResourceName: item.iconResourceName,
                            iconURLString: item.iconURLString,
                            fallbackSeed: item.name,
                            size: 28
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.billingKindValue == .lifetime ? "永久有效" : "尚未设置到期日期")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("订阅详情") { onDetails(item.id) }
                    Button("编辑订阅") { onEdit(item.id) }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }
}
