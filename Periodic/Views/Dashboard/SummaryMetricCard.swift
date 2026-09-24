import SwiftUI

struct SummaryMetricCard: View {
    let title: String
    let value: String
    var detail: String?
    let symbol: String
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开对应列表")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(AppLocalization.string(title))
            } icon: {
                Image(systemName: symbol)
            }
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
