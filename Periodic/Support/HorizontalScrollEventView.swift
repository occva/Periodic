import AppKit
import SwiftUI

struct HorizontalScrollEventView: NSViewRepresentable {
    let onScroll: @MainActor (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> HorizontalScrollCaptureView {
        HorizontalScrollCaptureView(onScroll: onScroll)
    }

    func updateNSView(_ view: HorizontalScrollCaptureView, context: Context) {
        view.onScroll = onScroll
    }

    static func dismantleNSView(_ view: HorizontalScrollCaptureView, coordinator: Void) {
        view.removeEventMonitor()
    }
}

@MainActor
final class HorizontalScrollCaptureView: NSView {
    var onScroll: @MainActor (CGFloat, CGFloat) -> Void
    private var eventMonitor: Any?

    init(onScroll: @escaping @MainActor (CGFloat, CGFloat) -> Void) {
        self.onScroll = onScroll
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeEventMonitor()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window,
              let deltaX = horizontalDelta(from: event),
              bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return event
        }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        onScroll(deltaX * scale, bounds.width)
        return nil
    }

    private func horizontalDelta(from event: NSEvent) -> CGFloat? {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            return event.scrollingDeltaX
        }
        if event.modifierFlags.contains(.shift), event.scrollingDeltaY != 0 {
            return event.scrollingDeltaY
        }
        return nil
    }
}
