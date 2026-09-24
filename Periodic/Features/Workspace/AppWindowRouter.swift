import AppKit
import Observation

enum MainWindowRoute: Equatable, Sendable {
    case dashboard(dueHorizon: DueHorizon?)
    case overview
    case subscriptionDetails(UUID)
    case newSubscription
    case templateLibrary
}

@MainActor
@Observable
final class AppWindowRouter {
    private final class WeakWindow {
        weak var value: NSWindow?

        init(_ value: NSWindow) {
            self.value = value
        }
    }

    private var windows: [UUID: WeakWindow] = [:]
    private var routes: [UUID: MainWindowRoute] = [:]
    private var pendingNewWindowRoute: MainWindowRoute?
    private(set) var routeRevision = 0

    func register(window: NSWindow, id: UUID) {
        windows[id] = WeakWindow(window)
        if let pendingNewWindowRoute {
            routes[id] = pendingNewWindowRoute
            self.pendingNewWindowRoute = nil
            routeRevision &+= 1
        }
    }

    func unregister(window: NSWindow, id: UUID) {
        guard windows[id]?.value === window else { return }
        windows[id] = nil
        routes[id] = nil
    }

    /// Returns true when an existing main window accepted the route.
    /// The caller should open a new main scene when this returns false.
    @discardableResult
    func request(_ route: MainWindowRoute) -> Bool {
        discardClosedWindows()
        guard let target = preferredWindow() else {
            pendingNewWindowRoute = route
            return false
        }
        routes[target.id] = route
        routeRevision &+= 1
        activate(target.window)
        return true
    }

    func consumeRoute(for windowID: UUID) -> MainWindowRoute? {
        routes.removeValue(forKey: windowID)
    }

    func activateApplication() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func terminateApplication() {
        NSApp.terminate(nil)
    }

    private func preferredWindow() -> (id: UUID, window: NSWindow)? {
        for orderedWindow in NSApp.orderedWindows {
            if let match = windows.first(where: { $0.value.value === orderedWindow }),
               !orderedWindow.isMiniaturized {
                return (match.key, orderedWindow)
            }
        }
        guard let match = windows.first(where: { $0.value.value != nil }),
              let window = match.value.value else {
            return nil
        }
        return (match.key, window)
    }

    private func discardClosedWindows() {
        let closedIDs = windows.compactMap { id, window in
            window.value == nil ? id : nil
        }
        for id in closedIDs {
            windows[id] = nil
            routes[id] = nil
        }
    }

    private func activate(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        activateApplication()
    }
}
