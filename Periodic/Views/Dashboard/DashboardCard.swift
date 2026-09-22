import SwiftUI

struct DashboardCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(AppLocalization.string(title))
            } icon: {
                Image(systemName: symbol)
            }
            .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
