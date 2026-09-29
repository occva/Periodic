import SwiftUI

struct DashboardCard<Content: View, HeaderAccessory: View>: View {
    let title: String
    let symbol: String
    private let titleAction: (() -> Void)?
    private let titleActionHint: String?
    private let headerAccessory: HeaderAccessory
    private let content: Content

    init(
        title: String,
        symbol: String,
        titleAction: (() -> Void)? = nil,
        titleActionHint: String? = nil,
        @ViewBuilder content: () -> Content
    ) where HeaderAccessory == EmptyView {
        self.title = title
        self.symbol = symbol
        self.titleAction = titleAction
        self.titleActionHint = titleActionHint
        self.headerAccessory = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        symbol: String,
        titleAction: (() -> Void)? = nil,
        titleActionHint: String? = nil,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.titleAction = titleAction
        self.titleActionHint = titleActionHint
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let titleAction {
                    Button(action: titleAction) {
                        titleLabel
                    }
                    .buttonStyle(.plain)
                    .help(titleActionHint.map(AppLocalization.string) ?? "")
                    .accessibilityLabel(
                        titleActionHint.map(AppLocalization.string)
                            ?? AppLocalization.string(title)
                    )
                    .accessibilityIdentifier("dashboard-card-title-action")
                } else {
                    titleLabel
                }
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

    private var titleLabel: some View {
        Label {
            Text(AppLocalization.string(title))
        } icon: {
            Image(systemName: symbol)
        }
        .font(.headline)
        .contentShape(Rectangle())
    }
}
