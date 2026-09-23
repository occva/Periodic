import AppKit
import SwiftUI

struct WindowRegistrationView: NSViewRepresentable {
    let windowID: UUID
    let router: AppWindowRouter

    func makeNSView(context: Context) -> RegistrationView {
        RegistrationView(windowID: windowID, router: router)
    }

    func updateNSView(_ view: RegistrationView, context: Context) {
        view.update(windowID: windowID, router: router)
    }

    static func dismantleNSView(_ view: RegistrationView, coordinator: Void) {
        view.unregisterCurrentWindow()
    }
}

@MainActor
final class RegistrationView: NSView {
    private var windowID: UUID
    private weak var router: AppWindowRouter?
    private weak var registeredWindow: NSWindow?

    init(windowID: UUID, router: AppWindowRouter) {
        self.windowID = windowID
        self.router = router
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerCurrentWindowIfNeeded()
    }

    func update(windowID: UUID, router: AppWindowRouter) {
        if self.windowID != windowID || self.router !== router {
            unregisterCurrentWindow()
            self.windowID = windowID
            self.router = router
        }
        registerCurrentWindowIfNeeded()
    }

    func unregisterCurrentWindow() {
        guard let registeredWindow else { return }
        router?.unregister(window: registeredWindow, id: windowID)
        self.registeredWindow = nil
    }

    private func registerCurrentWindowIfNeeded() {
        guard let window, registeredWindow !== window else { return }
        unregisterCurrentWindow()
        registeredWindow = window
        router?.register(window: window, id: windowID)
    }
}

