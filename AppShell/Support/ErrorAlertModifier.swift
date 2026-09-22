import SwiftUI

struct ErrorAlertModifier: ViewModifier {
    @Binding var error: PresentedError?

    func body(content: Content) -> some View {
        content.alert(
            error?.title ?? "操作未完成",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("好", role: .cancel) { error = nil }
        } message: { presentedError in
            Text(presentedError.message)
        }
    }
}

extension View {
    func errorAlert(_ error: Binding<PresentedError?>) -> some View {
        modifier(ErrorAlertModifier(error: error))
    }
}
