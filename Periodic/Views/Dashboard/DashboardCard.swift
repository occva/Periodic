import SwiftUI

struct DashboardCard<Content: View, HeaderAccessory: View>: View {
    let title: String
    let symbol: String
    private let headerAccessory: HeaderAccessory
    private let content: Content

    init(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) where HeaderAccessory == EmptyView {
        self.title = title
        self.symbol = symbol
        self.headerAccessory = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        symbol: String,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label {
                    Text(AppLocalization.string(title))
                } icon: {
                    Image(systemName: symbol)
                }
                .font(.headline)
                Spacer(minLength: 12)
                headerAccessory
            }
            .frame(minHeight: 32)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
