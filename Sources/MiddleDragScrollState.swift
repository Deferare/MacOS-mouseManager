import Cocoa
import Foundation

final class MiddleDragScrollState {
    private static let timestampToSecondsScale: Double = 1.0 / 1_000_000_000.0

    private var didDrag: Bool = false
    private var accumulatedAbsX: Double = 0
    private var accumulatedAbsY: Double = 0
    private var lastLocation: CGPoint?
    private var lastTimestamp: TimeInterval?
    private var velocityX: Double = 0
    private var velocityY: Double = 0
    private var middleAction: ButtonAction?

    static let syntheticUserDataTag: Int64 = 0x4D4D464D // "MMFM"
    private let dragThreshold: Double = 2.4
    private let velocityFilterBlend: Double = 0.46
    private let minimumMomentumSpeed: Double = 112.0
    private(set) var isActive: Bool = false

    enum ClickBehavior {
        case preserveClick
        case perform(ButtonAction)
    }

    enum EndResult {
        case click(ClickBehavior)
        case dragged(velocityX: Double, velocityY: Double)
        case none
    }

    private func resetState() {
        didDrag = false
        accumulatedAbsX = 0
        accumulatedAbsY = 0
        lastLocation = nil
        lastTimestamp = nil
        velocityX = 0
        velocityY = 0
        middleAction = nil
        isActive = false
    }

    func begin(event: CGEvent, middleAction: ButtonAction) {
        resetState()
        lastLocation = event.location
        lastTimestamp = eventTimestampSeconds(event)
        self.middleAction = middleAction
        isActive = true
    }

    func updateDrag(event: CGEvent) -> (dx: Double, dy: Double)? {
        // Prefer location-based delta; some devices report 0 for mouseEventDeltaX/Y on otherMouseDragged.
        let location = event.location
        let dx: Double
        let dy: Double
        if let lastLocation {
            dx = Double(location.x - lastLocation.x)
            dy = Double(location.y - lastLocation.y)
        } else {
            dx = event.getDoubleValueField(.mouseEventDeltaX)
            dy = event.getDoubleValueField(.mouseEventDeltaY)
        }
        lastLocation = location

        accumulatedAbsX += abs(dx)
        accumulatedAbsY += abs(dy)
        if accumulatedAbsX + accumulatedAbsY >= dragThreshold {
            didDrag = true
        }

        let now = eventTimestampSeconds(event)
        if didDrag, let lastTimestamp {
            let dt = max(1.0 / 500.0, min(0.05, now - lastTimestamp))
            let rawVelocityX = dx / dt
            let rawVelocityY = dy / dt
            velocityX = ((1.0 - velocityFilterBlend) * velocityX) + (velocityFilterBlend * rawVelocityX)
            velocityY = ((1.0 - velocityFilterBlend) * velocityY) + (velocityFilterBlend * rawVelocityY)
        }
        self.lastTimestamp = now

        // Don't emit scroll until we've crossed the drag threshold.
        if !didDrag {
            return nil
        }

        // Map mouse movement to scroll direction like touch:
        // dragging up should scroll down, dragging right should scroll left.
        //
        // Note: scroll delta sign conventions differ across apps; we align X with the same
        // convention as Y (already validated by user feedback).
        return (dx: dx, dy: dy)
    }

    func end(event: CGEvent) -> EndResult {
        _ = event
        defer {
            resetState()
        }
        guard isActive else { return .none }
        guard didDrag else {
            if let middleAction {
                return .click(.perform(middleAction))
            }
            return .click(.preserveClick)
        }

        let speed = hypot(velocityX, velocityY)
        guard speed >= minimumMomentumSpeed else {
            return .none
        }
        return .dragged(velocityX: velocityX, velocityY: velocityY)
    }

    func cancel() {
        resetState()
    }

    private func eventTimestampSeconds(_ event: CGEvent) -> TimeInterval {
        let timestamp = event.timestamp
        guard timestamp > 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        return Double(timestamp) * Self.timestampToSecondsScale
    }
}
