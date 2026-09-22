import SwiftUI

struct CreateSubscriptionAction {
    let perform: @MainActor () -> Void

    @MainActor
    func callAsFunction() {
        perform()
    }
}

private struct CreateSubscriptionActionKey: FocusedValueKey {
    typealias Value = CreateSubscriptionAction
}

extension FocusedValues {
    var createSubscriptionAction: CreateSubscriptionAction? {
        get { self[CreateSubscriptionActionKey.self] }
        set { self[CreateSubscriptionActionKey.self] = newValue }
    }
}
