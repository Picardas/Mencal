import AppKit
import SwiftUI

/// Swipes and scroll-wheel clicks over the calendar, passed from AppKit
/// (which receives them) to CalendarMenuView (which acts on them). Steps add
/// up until the view takes them, so clicks arriving between two updates
/// aren't lost and a fast-spinning wheel moves in one go.
@Observable
final class CalendarGestures {
    /// Changes with every step, so the view sees each one.
    private(set) var serial = 0
    @ObservationIgnored private var pendingSteps = 0

    /// Next (+1) or previous (-1) month, year or decade.
    func step(_ offset: Int) {
        pendingSteps += offset
        serial += 1
    }

    /// The steps since the last call.
    func takeSteps() -> Int {
        defer { pendingSteps = 0 }
        return pendingSteps
    }
}

/// Hosts the calendar in the menu, turning trackpad and mouse gestures into
/// calendar navigation. SwiftUI has no scroll-wheel events on macOS, so
/// they're caught here, where AppKit delivers them.
final class CalendarHostingView<Content: View>: NSHostingView<Content> {
    var gestures: CalendarGestures?

    /// How far fingers travel sideways before it counts.
    private static var swipeThreshold: CGFloat { 30 }

    private enum Direction { case undecided, sideways, vertical }

    /// Decided at the start of each gesture, so a vertical scroll that
    /// drifts sideways never becomes a swipe.
    private var direction = Direction.undecided
    private var swipeDistance: CGFloat = 0
    /// One step per swipe, however far it goes.
    private var hasSwiped = false
    private var lastScrollTimestamp: TimeInterval = 0

    override func scrollWheel(with event: NSEvent) {
        guard let gestures else { return super.scrollWheel(with: event) }

        guard event.hasPreciseScrollingDeltas else {
            // A mouse wheel: each click moves one step, as in Windows.
            // Rolling it down (towards you) goes forward, whatever the scroll
            // direction setting, just as fingers do below.
            let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            guard delta != 0 else { return }
            let rolledDown = event.isDirectionInvertedFromDevice ? delta > 0 : delta < 0
            gestures.step(rolledDown ? 1 : -1)
            return
        }

        // A trackpad or Magic Mouse. The coast after lifting the fingers
        // isn't part of the swipe.
        guard event.momentumPhase.isEmpty else { return }
        // A new gesture starts with .began or, on devices that report no
        // phases, after a pause.
        let isNewGesture = event.phase.contains(.began)
            || (event.phase.isEmpty && event.timestamp - lastScrollTimestamp > 0.3)
        lastScrollTimestamp = event.timestamp
        if isNewGesture { resetSwipe() }
        defer { if event.phase.contains(.ended) || event.phase.contains(.cancelled) { resetSwipe() } }

        if direction == .undecided {
            let sideways = abs(event.scrollingDeltaX), vertical = abs(event.scrollingDeltaY)
            guard sideways + vertical > 0 else { return }
            direction = sideways > vertical ? .sideways : .vertical
        }
        // Honour System Settings › Trackpad › Swipe between pages.
        guard direction == .sideways, NSEvent.isSwipeTrackingFromScrollEventsEnabled else {
            return super.scrollWheel(with: event)
        }
        guard !hasSwiped else { return }
        // By finger direction, like swiping between pages, whatever the
        // scroll direction setting.
        swipeDistance += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if abs(swipeDistance) > Self.swipeThreshold {
            hasSwiped = true
            // Fingers moving towards the start of the line (left, or right in
            // right-to-left languages) bring in what comes next.
            let towardsStart = userInterfaceLayoutDirection == .rightToLeft ? swipeDistance > 0 : swipeDistance < 0
            gestures.step(towardsStart ? 1 : -1)
        }
    }

    private func resetSwipe() {
        direction = .undecided
        swipeDistance = 0
        hasSwiped = false
    }
}
