import Cocoa
import Foundation
import os.lock

final class SharedTapContext {
    private static let wheelDeltaEpsilon: Double = 0.000_1
    private static let passthroughIntScale: Double = 6.0
    private static let wheelAdaptiveGainLowSpeedBoost: Double = 1.55
    private static let wheelAdaptiveGainHighSpeedDamping: Double = 0.70
    private static let wheelAdaptiveGainKnee: Double = 2.0
    private static let middleDragGainX: Double = 0.98
    private static let middleDragGainY: Double = 1.45
    private static let middleDragAdaptiveGainSpan: Double = 0.22
    private static let middleDragAdaptiveGainKnee: Double = 9.0
    private static let middleDragPrecisionDampingSpan: Double = 0.10
    private static let middleDragPrecisionKnee: Double = 1.6
    private static let swallowMiddleButtonBit: UInt8 = 1 << 0
    private static let swallowButton4Bit: UInt8 = 1 << 1
    private static let swallowButton5Bit: UInt8 = 1 << 2

    private let lock = OSAllocatedUnfairLock()
    private var settings: SettingsSnapshot
    private let scrollSmoother = ScrollSmoother()
    private let middleDrag = MiddleDragScrollState()
    private let middleDragMomentum = MiddleDragMomentumAnimator()
    private var swallowedButtonsMask: UInt8 = 0
    private var eventTap: CFMachPort?
    private var interceptionEnabled: Bool = true

    init(settings: SettingsSnapshot) {
        self.settings = settings
        middleDragMomentum.updateStrength(level: settings.middleDragInertiaStrength)
    }

    func attachEventTap(_ tap: CFMachPort) {
        lock.lock()
        eventTap = tap
        lock.unlock()
    }

    func updateSettings(_ newSettings: SettingsSnapshot) {
        lock.lock()
        let previous = settings
        settings = newSettings
        lock.unlock()

        let smoothnessChanged = previous.smoothnessLevel != newSettings.smoothnessLevel
        let inertiaStrengthChanged = previous.middleDragInertiaStrength != newSettings.middleDragInertiaStrength

        // Prevent stale smoothing momentum from fighting new direction/mode settings.
        if previous.reverseDirection != newSettings.reverseDirection ||
            previous.smoothScrollingEnabled != newSettings.smoothScrollingEnabled {
            scrollSmoother.reset()
        }
        if previous.reverseDirection != newSettings.reverseDirection ||
            previous.middleDragScrollingEnabled != newSettings.middleDragScrollingEnabled {
            middleDragMomentum.cancel()
        }
        if inertiaStrengthChanged {
            middleDragMomentum.updateStrength(level: newSettings.middleDragInertiaStrength)
        }
        if smoothnessChanged {
            scrollSmoother.updateSmoothness(level: newSettings.smoothnessLevel)
        }
    }

    func setInterceptionEnabled(_ enabled: Bool) {
        lock.lock()
        let changed = interceptionEnabled != enabled
        interceptionEnabled = enabled
        if !enabled {
            swallowedButtonsMask = 0
        }
        lock.unlock()

        if changed, !enabled {
            middleDrag.cancel()
            middleDragMomentum.cancel()
            scrollSmoother.reset()
        }
    }

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = eventTap
            lock.unlock()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            // Drop any in-flight synthetic state because we may have missed a matching
            // middle-button up while the tap was disabled.
            middleDrag.cancel()
            middleDragMomentum.cancel()
            scrollSmoother.reset()
            return Unmanaged.passUnretained(event)
        }

        if type == .mouseMoved && !middleDrag.isActive {
            // mouseMoved is very high-frequency. Fast-path pass-through when drag mode is inactive.
            return Unmanaged.passUnretained(event)
        }

        // Synthetic events do not require settings/lock inspection.
        let userData = event.getIntegerValueField(.eventSourceUserData)
        if userData == ScrollSmoother.syntheticUserDataTag || userData == MiddleDragScrollState.syntheticUserDataTag {
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let currentSettings = settings
        let enabled = interceptionEnabled
        lock.unlock()
        if !enabled {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .scrollWheel:
            return handleScroll(event, settings: currentSettings)
        case .mouseMoved:
            return handleMouseMoved(event, settings: currentSettings)
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return handleOtherButtons(type: type, event: event, settings: currentSettings)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleMouseMoved(_ event: CGEvent, settings: SettingsSnapshot) -> Unmanaged<CGEvent>? {
        reconcileMiddleDragIfNeeded()

        guard settings.middleDragScrollingEnabled, middleDrag.isActive else {
            return Unmanaged.passUnretained(event)
        }

        if let scrollDelta = middleDrag.updateDrag(event: event) {
            handleMiddleDragScroll(
                deltaX: scrollDelta.dx,
                deltaY: scrollDelta.dy,
                reverseDirection: settings.reverseDirection
            )
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleScroll(_ event: CGEvent, settings: SettingsSnapshot) -> Unmanaged<CGEvent>? {
        reconcileMiddleDragIfNeeded()

        // While middle-button drag mode is active, don't apply wheel smoothing.
        if middleDrag.isActive {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        // Do not interfere with app-switcher / command-shortcut interactions.
        if flags.contains(.maskCommand) {
            return Unmanaged.passUnretained(event)
        }

        var (deltaX, deltaY) = readWheelDelta(from: event)
        if flags.contains(.maskShift), abs(deltaX) < Self.wheelDeltaEpsilon, abs(deltaY) > Self.wheelDeltaEpsilon {
            // Many wheels emit only vertical delta with Shift held. Convert to horizontal explicitly.
            deltaX = deltaY
            deltaY = 0
        }

        if settings.reverseDirection {
            deltaY = -deltaY
            deltaX = -deltaX
        }

        // Boost small wheel movement for better low-speed control, while damping
        // larger bursts to avoid excessive acceleration.
        let adaptiveGain = adaptiveWheelGain(deltaX: deltaX, deltaY: deltaY)
        deltaY *= settings.speedMultiplier * adaptiveGain
        deltaX *= settings.speedMultiplier * adaptiveGain

        // Guard against rare driver/device anomalies that may yield non-finite deltas.
        if !deltaY.isFinite || !deltaX.isFinite {
            return Unmanaged.passUnretained(event)
        }

        // Never swallow an event when the effective delta is zero-like.
        if abs(deltaY) < Self.wheelDeltaEpsilon && abs(deltaX) < Self.wheelDeltaEpsilon {
            return Unmanaged.passUnretained(event)
        }

        if !settings.smoothScrollingEnabled {
            applyScrollDelta(to: event, deltaX: deltaX, deltaY: deltaY, intScale: Self.passthroughIntScale)
            return Unmanaged.passUnretained(event)
        }

        // Smooth scrolling: suppress original event and replay a decaying velocity stream.
        scrollSmoother.enqueueImpulse(
            deltaX: deltaX,
            deltaY: deltaY,
            continuous: true,
            smoothnessLevel: settings.smoothnessLevel,
            flags: flags
        )
        return nil
    }

    private func readWheelDelta(from event: CGEvent) -> (deltaX: Double, deltaY: Double) {
        // Point deltas can be near-zero on some wheel devices.
        let pointY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let pointX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        if abs(pointY) > Self.wheelDeltaEpsilon || abs(pointX) > Self.wheelDeltaEpsilon {
            return (deltaX: pointX, deltaY: pointY)
        }

        let fixedY = Double(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)) / 65536.0
        let fixedX = Double(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2)) / 65536.0
        if abs(fixedY) > Self.wheelDeltaEpsilon || abs(fixedX) > Self.wheelDeltaEpsilon {
            return (deltaX: fixedX, deltaY: fixedY)
        }

        return (
            deltaX: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            deltaY: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        )
    }

    private func applyScrollDelta(to event: CGEvent, deltaX: Double, deltaY: Double, intScale: Double) {
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: deltaY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: deltaX)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64((deltaY * intScale).rounded()))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64((deltaX * intScale).rounded()))
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Int64((deltaY * 65536.0).rounded()))
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Int64((deltaX * 65536.0).rounded()))
    }

    private func adaptiveWheelGain(deltaX: Double, deltaY: Double) -> Double {
        let magnitude = max(abs(deltaX), abs(deltaY))
        let lowBoost = Self.wheelAdaptiveGainLowSpeedBoost
        let highDamping = Self.wheelAdaptiveGainHighSpeedDamping
        let response = highDamping + ((lowBoost - highDamping) * exp(-magnitude / Self.wheelAdaptiveGainKnee))
        return min(lowBoost, max(highDamping, response))
    }

    private func adjustMiddleDrag(deltaX: Double, deltaY: Double, reverseDirection: Bool) -> (dx: Double, dy: Double) {
        // Apply low-speed precision damping + high-speed gain for a trackpad-like hand feel.
        let magnitude = hypot(deltaX, deltaY)
        let adaptiveGain = 1.0 + (Self.middleDragAdaptiveGainSpan * (1.0 - exp(-magnitude / Self.middleDragAdaptiveGainKnee)))
        let precisionDamping = 1.0 - (Self.middleDragPrecisionDampingSpan * exp(-magnitude / Self.middleDragPrecisionKnee))
        let response = adaptiveGain * precisionDamping

        // Middle-button drag is touch-like and intentionally stronger on Y.
        var adjustedX = deltaX * Self.middleDragGainX * response
        var adjustedY = deltaY * Self.middleDragGainY * response
        if reverseDirection {
            adjustedX = -adjustedX
            adjustedY = -adjustedY
        }
        return (dx: adjustedX, dy: adjustedY)
    }

    private func handleMiddleDragScroll(deltaX: Double, deltaY: Double, reverseDirection: Bool) {
        let adjusted = adjustMiddleDrag(deltaX: deltaX, deltaY: deltaY, reverseDirection: reverseDirection)
        postImmediateScroll(deltaX: adjusted.dx, deltaY: adjusted.dy, continuous: true, intScaleX: 10.0, intScaleY: 12.0)
    }

    private func handleOtherButtons(type: CGEventType, event: CGEvent, settings: SettingsSnapshot) -> Unmanaged<CGEvent>? {
        // buttonNumber: 2 = middle, 3 = button4, 4 = button5 (common mapping).
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        switch type {
        case .otherMouseDown:
            if buttonNumber == 2, settings.middleDragScrollingEnabled {
                middleDragMomentum.cancel()
                middleDrag.begin(event: event, middleAction: settings.middleClickAction)
                return nil
            }
            if handleOtherButtonDown(buttonNumber: buttonNumber, settings: settings) {
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .otherMouseDragged:
            if buttonNumber == 2, settings.middleDragScrollingEnabled {
                if let scrollDelta = middleDrag.updateDrag(event: event) {
                    handleMiddleDragScroll(
                        deltaX: scrollDelta.dx,
                        deltaY: scrollDelta.dy,
                        reverseDirection: settings.reverseDirection
                    )
                }
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .otherMouseUp:
            if buttonNumber == 2, settings.middleDragScrollingEnabled {
                switch middleDrag.end(event: event) {
                case .click(let clickBehavior):
                    switch clickBehavior {
                    case .perform(let action):
                        if action != .none {
                            perform(action: action)
                        } else {
                            // Preserve normal click when action is None/unknown.
                            postSyntheticMiddleClick()
                        }
                    case .preserveClick:
                        postSyntheticMiddleClick()
                    }
                case .dragged(let velocityX, let velocityY):
                    let adjusted = adjustMiddleDrag(deltaX: velocityX, deltaY: velocityY, reverseDirection: settings.reverseDirection)
                    middleDragMomentum.start(velocityX: adjusted.dx, velocityY: adjusted.dy, flags: event.flags)
                case .none:
                    break
                }
                return nil
            }
            let shouldSwallow: Bool
            if let bit = Self.swallowBit(for: buttonNumber) {
                lock.lock()
                shouldSwallow = (swallowedButtonsMask & bit) != 0
                swallowedButtonsMask &= ~bit
                lock.unlock()
            } else {
                shouldSwallow = false
            }
            return shouldSwallow ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func reconcileMiddleDragIfNeeded() {
        guard middleDrag.isActive else { return }
        // If we missed otherMouseUp while the tap was briefly disabled, recover here.
        if !CGEventSource.buttonState(.combinedSessionState, button: .center) {
            middleDrag.cancel()
        }
    }

    private func handleOtherButtonDown(buttonNumber: Int64, settings: SettingsSnapshot) -> Bool {
        guard let action = mappedAction(for: buttonNumber, settings: settings) else {
            return false
        }

        guard action != .none else {
            return false
        }

        perform(action: action)
        if let bit = Self.swallowBit(for: buttonNumber) {
            lock.lock()
            swallowedButtonsMask |= bit
            lock.unlock()
        }
        return true
    }

    private func mappedAction(for buttonNumber: Int64, settings: SettingsSnapshot) -> ButtonAction? {
        switch buttonNumber {
        case 2: return settings.middleClickAction
        case 3: return settings.button4ClickAction
        case 4: return settings.button5ClickAction
        default: return nil
        }
    }

    private static func swallowBit(for buttonNumber: Int64) -> UInt8? {
        switch buttonNumber {
        case 2: return swallowMiddleButtonBit
        case 3: return swallowButton4Bit
        case 4: return swallowButton5Bit
        default: return nil
        }
    }

    private func perform(action: ButtonAction) {
        switch action {
        case .none:
            return
        case .back:
            postKeyCombo(keyCode: 0x21 /* [ */, flags: .maskCommand)
        case .forward:
            postKeyCombo(keyCode: 0x1E /* ] */, flags: .maskCommand)
        case .missionControl:
            postKeyCombo(keyCode: 0x7E /* ↑ */, flags: .maskControl)
        case .appExpose:
            postKeyCombo(keyCode: 0x7D /* ↓ */, flags: .maskControl)
        case .lookUpQuickLook:
            postKeyCombo(keyCode: 0x02 /* D */, flags: [.maskControl, .maskCommand])
        }
    }

    private func postKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = SyntheticEventSource.hidSystemState else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
    }

    private func postImmediateScroll(deltaX: Double, deltaY: Double, continuous: Bool, intScaleX: Double = 6.0, intScaleY: Double = 6.0, flags: CGEventFlags = []) {
        // Send a single scroll event without additional smoothing.
        ScrollSmoother.postScroll(deltaX: deltaX, deltaY: deltaY, continuous: continuous, intScaleX: intScaleX, intScaleY: intScaleY, flags: flags)
    }

    private func postSyntheticMiddleClick() {
        // We swallowed the original middle mouse down/up so that dragging can be repurposed.
        // If it turns out it was just a click, re-post a normal middle click to the system.
        guard let source = SyntheticEventSource.hidSystemState else { return }
        let location = CGEvent(source: source)?.location ?? .zero

        guard
            let down = CGEvent(mouseEventSource: source, mouseType: .otherMouseDown, mouseCursorPosition: location, mouseButton: .center),
            let up = CGEvent(mouseEventSource: source, mouseType: .otherMouseUp, mouseCursorPosition: location, mouseButton: .center)
        else { return }

        down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        up.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        down.setIntegerValueField(.eventSourceUserData, value: MiddleDragScrollState.syntheticUserDataTag)
        up.setIntegerValueField(.eventSourceUserData, value: MiddleDragScrollState.syntheticUserDataTag)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
