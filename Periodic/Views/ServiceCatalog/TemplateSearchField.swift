import AppKit
import SwiftUI

@MainActor
struct TemplateSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField(frame: .zero)
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchTextChanged(_:))
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.text = $text
        let prompt = AppLocalization.string("搜索模板名称或别名")
        searchField.placeholderString = prompt
        searchField.setAccessibilityLabel(prompt)
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSSearchField,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? max(nsView.intrinsicContentSize.width, 0),
            height: nsView.intrinsicContentSize.height
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func searchTextChanged(_ searchField: NSSearchField) {
            text.wrappedValue = searchField.stringValue
        }
    }
}
