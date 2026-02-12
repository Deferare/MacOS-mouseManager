import Cocoa
import CoreVideo
import Foundation

private enum SyntheticEventSource {
    static let hidSystemState: CGEventSource? = CGEventSource(stateID: .hidSystemState)
}

final class SharedTapContext {
    private static let wheelDeltaEpsilon: Double = 0.000_1
    private static let passthroughIntScale: Double = 6.0
    private static let wheelAdaptiveGainLowSpeedBoost: Double = 1.55
    private static let wheelAdaptiveGainHighSpeedDamping: Double = 0.70
    private static let wheelAdaptiveGainKnee: Double = 2.0

    private let lock = NSLock()
    private var settings: SettingsSnapshot
    private let scrollSmoother = ScrollSmoother()
    private let middleDrag = MiddleDragScrollState()
    private let middleDragMomentum = MiddleDragMomentumAnimator()
    private var swallowedButtonNumbers = Set<Int64>()
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

        // Prevent stale smoothing momentum from fighting new direction/mode settings.
        if previous.reverseDirection != newSettings.reverseDirection ||
            previous.smoothScrollingEnabled != newSettings.smoothScrollingEnabled {
            scrollSmoother.reset()
        }
        if previous.reverseDirection != newSettings.reverseDirection ||
            previous.middleDragScrollingEnabled != newSettings.middleDragScrollingEnabled {
            middleDragMomentum.cancel()
        }
        middleDragMomentum.updateStrength(level: newSettings.middleDragInertiaStrength)
        scrollSmoother.updateSmoothness(level: newSettings.smoothnessLevel)
    }

    func setInterceptionEnabled(_ enabled: Bool) {
        lock.lock()
        let changed = interceptionEnabled != enabled
        interceptionEnabled = enabled
        if !enabled {
            swallowedButtonNumbers.removeAll()
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

        lock.lock()
        let currentSettings = settings
        let enabled = interceptionEnabled
        lock.unlock()
        if !enabled {
            return Unmanaged.passUnretained(event)
        }

        // Avoid re-processing events we synthesize ourselves.
        let userData = event.getIntegerValueField(.eventSourceUserData)
        if userData == ScrollSmoother.syntheticUserDataTag || userData == MiddleDragScrollState.syntheticUserDataTag {
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
        // Middle-button drag is touch-like and intentionally stronger on Y.
        var adjustedX = deltaX
        var adjustedY = deltaY * 1.6
        if reverseDirection {
            adjustedX = -adjustedX
            adjustedY = -adjustedY
        }
        return (dx: adjustedX, dy: adjustedY)
    }

    private func handleMiddleDragScroll(deltaX: Double, deltaY: Double, reverseDirection: Bool) {
        let adjusted = adjustMiddleDrag(deltaX: deltaX, deltaY: deltaY, reverseDirection: reverseDirection)
        postImmediateScroll(deltaX: adjusted.dx, deltaY: adjusted.dy, continuous: true, intScaleX: 1.0, intScaleY: 4.0)
    }

    private func handleOtherButtons(type: CGEventType, event: CGEvent, settings: SettingsSnapshot) -> Unmanaged<CGEvent>? {
        // buttonNumber: 2 = middle, 3 = button4, 4 = button5 (common mapping).
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        switch type {
        case .otherMouseDown:
            if buttonNumber == 2, settings.middleDragScrollingEnabled {
                middleDragMomentum.cancel()
                middleDrag.begin(event: event, middleAction: settings.middleClickButtonAction)
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
            lock.lock()
            let shouldSwallow = swallowedButtonNumbers.remove(buttonNumber) != nil
            lock.unlock()
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
        lock.lock()
        swallowedButtonNumbers.insert(buttonNumber)
        lock.unlock()
        return true
    }

    private func mappedAction(for buttonNumber: Int64, settings: SettingsSnapshot) -> ButtonAction? {
        switch buttonNumber {
        case 2: return settings.middleClickButtonAction
        case 3: return settings.button4ButtonAction
        case 4: return settings.button5ButtonAction
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

private final class ScrollSmoother {
    static let syntheticUserDataTag: Int64 = 0x4D4D4653 // "MMFS"

    private let queue = DispatchQueue(label: "mousemanager.scrollsmoother")
    private var displayLink: CVDisplayLink?
    private var isRunning: Bool = false

    // Remaining delta that we will distribute across several display frames.
    // This gives "touch-like" smoothness but stops quickly once input stops.
    private var remainingX: Double = 0
    private var remainingY: Double = 0
    // Preserve sub-integer wheel movement so small deltas are not lost.
    private var carryScaledX: Double = 0
    private var carryScaledY: Double = 0

    private var continuous: Bool = true
    private var tuning = Tuning.defaultValue
    private var outputFlags: CGEventFlags = []
    private var smoothnessLevel: Double = 0.68
    private var nominalFrameDurationSeconds: Double = 1.0 / 120.0

    private func clearBufferedMotion() {
        remainingX = 0
        remainingY = 0
        carryScaledX = 0
        carryScaledY = 0
    }

    private struct Tuning {
        let tauSeconds: Double
        let stopEpsilon: Double
        let outputScaleX: Double
        let outputScaleY: Double

        static let defaultValue = from(level: 0.68)

        static func from(level: Double) -> Tuning {
            let s = max(0.0, min(1.0, level))
            let tauSeconds = 0.055 + (0.150 * s)
            let stopEpsilon = 0.0026 - (0.0022 * s)
            let outputScale = 10.0 + (8.0 * s)
            return Tuning(
                tauSeconds: tauSeconds,
                stopEpsilon: max(0.00025, stopEpsilon),
                outputScaleX: outputScale,
                outputScaleY: outputScale
            )
        }
    }

    func reset() {
        queue.async {
            self.clearBufferedMotion()
            self.stopIfNeeded()
        }
    }

    func updateSmoothness(level: Double) {
        queue.async {
            guard self.smoothnessLevel != level else { return }
            self.smoothnessLevel = level
            self.tuning = Tuning.from(level: level)
        }
    }

    func enqueueImpulse(deltaX: Double, deltaY: Double, continuous: Bool, smoothnessLevel: Double, flags: CGEventFlags) {
        queue.async {
            self.continuous = continuous
            if self.smoothnessLevel != smoothnessLevel {
                self.smoothnessLevel = smoothnessLevel
                self.tuning = Tuning.from(level: smoothnessLevel)
            }
            self.outputFlags = flags

            // Accumulate impulse to be smoothed out over subsequent frames.
            self.remainingX += deltaX
            self.remainingY += deltaY

            self.startIfNeeded()
        }
    }

    private func startIfNeeded() {
        if isRunning { return }
        isRunning = true

        if displayLink == nil {
            var link: CVDisplayLink?
            CVDisplayLinkCreateWithActiveCGDisplays(&link)
            displayLink = link

            if let displayLink {
                CVDisplayLinkSetOutputCallback(displayLink, { (_, _, _, _, _, userInfo) -> CVReturn in
                    guard let userInfo else { return kCVReturnSuccess }
                    let unmanaged = Unmanaged<ScrollSmoother>.fromOpaque(userInfo)
                    let smoother = unmanaged.takeUnretainedValue()
                    smoother.frameTick()
                    return kCVReturnSuccess
                }, Unmanaged.passUnretained(self).toOpaque())

                let nominal = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink)
                if nominal.timeValue > 0 {
                    nominalFrameDurationSeconds = Double(nominal.timeValue) / Double(nominal.timeScale)
                } else {
                    nominalFrameDurationSeconds = 1.0 / 120.0
                }
            }
        }

        if let displayLink {
            CVDisplayLinkStart(displayLink)
        }
    }

    private func stopIfNeeded() {
        guard isRunning else { return }
        isRunning = false
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }

    private func frameTick() {
        // CVDisplayLink callback thread -> hop onto our queue.
        queue.async { [weak self] in
            self?.tick(dt: nil)
        }
    }

    private func tick(dt: Double?) {
        // If Command is held (e.g. App Switcher), stop synthetic scroll immediately.
        if CGEventSource.flagsState(.hidSystemState).contains(.maskCommand) {
            clearBufferedMotion()
            stopIfNeeded()
            return
        }

        // dt: we can derive from display link, but using a stable ~frame time works well for feel.
        // If dt not provided, approximate using display refresh period if available.
        let dtSeconds: Double
        if let dt {
            dtSeconds = max(1.0 / 240.0, min(1.0 / 30.0, dt))
        } else if displayLink != nil {
            dtSeconds = nominalFrameDurationSeconds
        } else {
            dtSeconds = 1.0 / 120.0
        }

        // Smooth by distributing remaining delta with a 1st-order low-pass style step response.
        // alpha = 1 - exp(-dt/tau)  -> fraction to emit this frame.
        let alpha = 1.0 - exp(-dtSeconds / tuning.tauSeconds)

        let frameX = remainingX * alpha
        let frameY = remainingY * alpha
        remainingX -= frameX
        remainingY -= frameY

        // Stop when it's effectively zero.
        if abs(remainingX) < tuning.stopEpsilon && abs(remainingY) < tuning.stopEpsilon {
            remainingX = 0
            remainingY = 0
            flushCarryIfNeeded()
            stopIfNeeded()
        }

        // Preserve tiny movement in carry and emit once enough accumulates.
        if abs(frameX) < 0.000_1 && abs(frameY) < 0.000_1 {
            return
        }

        postSmoothedScroll(
            deltaX: frameX,
            deltaY: frameY,
            continuous: continuous,
            intScaleX: tuning.outputScaleX,
            intScaleY: tuning.outputScaleY
        )
    }

    private func postSmoothedScroll(deltaX: Double, deltaY: Double, continuous: Bool, intScaleX: Double, intScaleY: Double) {
        carryScaledX += deltaX * intScaleX
        carryScaledY += deltaY * intScaleY

        let intX = Int32(carryScaledX.rounded())
        let intY = Int32(carryScaledY.rounded())
        if intX == 0 && intY == 0 {
            return
        }

        carryScaledX -= Double(intX)
        carryScaledY -= Double(intY)
        Self.postScroll(
            deltaX: Double(intX) / intScaleX,
            deltaY: Double(intY) / intScaleY,
            continuous: continuous,
            intScaleX: intScaleX,
            intScaleY: intScaleY,
            flags: outputFlags
        )
    }

    private func flushCarryIfNeeded() {
        let flushX = Int32(carryScaledX.rounded())
        let flushY = Int32(carryScaledY.rounded())
        guard flushX != 0 || flushY != 0 else { return }

        carryScaledX = 0
        carryScaledY = 0
        Self.postScroll(
            deltaX: Double(flushX) / tuning.outputScaleX,
            deltaY: Double(flushY) / tuning.outputScaleY,
            continuous: continuous,
            intScaleX: tuning.outputScaleX,
            intScaleY: tuning.outputScaleY,
            flags: outputFlags
        )
    }

    static func postScroll(deltaX: Double, deltaY: Double, continuous: Bool, intScaleX: Double, intScaleY: Double, flags: CGEventFlags = []) {
        guard let source = SyntheticEventSource.hidSystemState else { return }

        // CGScrollWheelEventDeltaAxis1/2 is integer-based, but PointDeltaAxis is Double.
        // Use pixel units. Some apps rely more on integer deltas than PointDelta.
        let intY = Int32((deltaY * intScaleY).rounded())
        let intX = Int32((deltaX * intScaleX).rounded())
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: intY, wheel2: intX, wheel3: 0) else {
            return
        }

        // Populate multiple fields for better compatibility across apps.
        e.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(intY))
        e.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(intX))
        e.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Int64((deltaY * 65536.0).rounded()))
        e.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Int64((deltaX * 65536.0).rounded()))
        e.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: deltaY)
        e.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: deltaX)
        e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticUserDataTag)
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }
}

private final class MiddleDragScrollState {
    private var didDrag: Bool = false
    private var accumulatedAbsX: Double = 0
    private var accumulatedAbsY: Double = 0
    private var lastLocation: CGPoint?
    private var lastTimestamp: TimeInterval?
    private var velocityX: Double = 0
    private var velocityY: Double = 0
    private var middleAction: ButtonAction?

    static let syntheticUserDataTag: Int64 = 0x4D4D464D // "MMFM"
    private let dragThreshold: Double = 3.0
    private let velocityFilterBlend: Double = 0.55
    private let minimumMomentumSpeed: Double = 140.0
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
        lastTimestamp = ProcessInfo.processInfo.systemUptime
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

        let now = ProcessInfo.processInfo.systemUptime
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
}

private final class MiddleDragMomentumAnimator {
    private let queue = DispatchQueue(label: "mousemanager.middledragmomentum")
    private var timer: DispatchSourceTimer?
    private var velocityX: Double = 0
    private var velocityY: Double = 0
    private var carryScaledX: Double = 0
    private var carryScaledY: Double = 0
    private var outputFlags: CGEventFlags = []
    private var strengthLevel: Double = 0.5
    private var lastTickTime: TimeInterval?
    private var quietTicks: Int = 0

    private static let minimumDtSeconds: Double = 1.0 / 240.0
    private static let maximumDtSeconds: Double = 1.0 / 30.0
    private let momentumOutputScaleX: Double = 28.0
    private let momentumOutputScaleY: Double = 32.0
    private let quietTicksToStop: Int = 20
    private let minimumLaunchSpeed: Double = 28.0
    private let minimumActiveSpeed: Double = 0.9
    private let maxLaunchSpeed: Double = 6_800.0
    private let decelerationReferenceSpeed: Double = 2_600.0

    func updateStrength(level: Double) {
        queue.async {
            self.strengthLevel = max(0.0, min(1.0, level))
            if self.strengthLevel <= 0.0 {
                self.stopLocked()
            }
        }
    }

    func start(velocityX: Double, velocityY: Double, flags: CGEventFlags) {
        queue.async {
            guard self.strengthLevel > 0.0 else {
                self.stopLocked()
                return
            }

            var launchVX = velocityX * self.launchScale
            var launchVY = velocityY * self.launchScale
            let speed = hypot(launchVX, launchVY)
            guard speed >= self.minimumLaunchSpeed else {
                self.stopLocked()
                return
            }

            if speed > self.maxLaunchSpeed {
                let clampScale = self.maxLaunchSpeed / speed
                launchVX *= clampScale
                launchVY *= clampScale
            }

            self.outputFlags = flags
            self.velocityX = launchVX
            self.velocityY = launchVY
            self.startTimerIfNeeded()
        }
    }

    func cancel() {
        queue.async {
            self.stopLocked()
        }
    }

    private func startTimerIfNeeded() {
        if timer != nil { return }

        lastTickTime = nil
        quietTicks = 0
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        // Run fast enough not to under-sample high-refresh displays; per-tick dt
        // is still measured from real elapsed time for stable decay/integration.
        newTimer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(2))
        newTimer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = newTimer
        newTimer.resume()
    }

    private func tick() {
        if CGEventSource.flagsState(.hidSystemState).contains(.maskCommand) {
            stopLocked()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let dtSeconds: Double
        if let lastTickTime {
            dtSeconds = min(Self.maximumDtSeconds, max(Self.minimumDtSeconds, now - lastTickTime))
        } else {
            dtSeconds = 1.0 / 144.0
        }
        lastTickTime = now

        let speed = hypot(velocityX, velocityY)
        let frameX = velocityX * dtSeconds
        let frameY = velocityY * dtSeconds
        let emitted = postMomentumScroll(deltaX: frameX, deltaY: frameY)

        // Use speed-adaptive decay: glide at high speed, then settle decisively near zero.
        let decay = pow(decelerationRatePerMillisecond(forSpeed: speed), dtSeconds * 1_000.0)
        velocityX *= decay
        velocityY *= decay

        // Don't hard-stop at a single threshold. Stop only after a short quiet tail.
        if speed < minimumActiveSpeed {
            quietTicks = emitted ? 0 : (quietTicks + 1)
        } else {
            quietTicks = 0
        }

        if quietTicks >= quietTicksToStop {
            stopLocked()
        }
    }

    private func postMomentumScroll(deltaX: Double, deltaY: Double) -> Bool {
        carryScaledX += deltaX * momentumOutputScaleX
        carryScaledY += deltaY * momentumOutputScaleY

        let intX = Int32(carryScaledX.rounded())
        let intY = Int32(carryScaledY.rounded())
        if intX == 0 && intY == 0 {
            return false
        }

        carryScaledX -= Double(intX)
        carryScaledY -= Double(intY)
        ScrollSmoother.postScroll(
            deltaX: Double(intX) / momentumOutputScaleX,
            deltaY: Double(intY) / momentumOutputScaleY,
            continuous: true,
            intScaleX: momentumOutputScaleX,
            intScaleY: momentumOutputScaleY,
            flags: outputFlags
        )
        return true
    }

    private func flushCarryIfNeeded() {
        let flushX = Int32(carryScaledX.rounded())
        let flushY = Int32(carryScaledY.rounded())
        guard flushX != 0 || flushY != 0 else { return }

        carryScaledX = 0
        carryScaledY = 0
        ScrollSmoother.postScroll(
            deltaX: Double(flushX) / momentumOutputScaleX,
            deltaY: Double(flushY) / momentumOutputScaleY,
            continuous: true,
            intScaleX: momentumOutputScaleX,
            intScaleY: momentumOutputScaleY,
            flags: outputFlags
        )
    }

    private var launchScale: Double {
        // Keep release speed close to drag velocity for a stronger touch-like handoff.
        0.44 + (0.86 * strengthResponse)
    }

    private func decelerationRatePerMillisecond(forSpeed speed: Double) -> Double {
        // Blend between low-speed and high-speed decay rates.
        // Near zero: stronger braking to avoid a long "crawl".
        // High speed: gentler braking for a richer glide.
        let normalized = min(1.0, max(0.0, speed / decelerationReferenceSpeed))
        let curve = pow(normalized, 0.58)
        let lowSpeedRate = 0.9946 + (0.0024 * strengthResponse)
        let highSpeedRate = 0.9971 + (0.0022 * strengthResponse)
        return lowSpeedRate + ((highSpeedRate - lowSpeedRate) * curve)
    }

    private var strengthResponse: Double {
        pow(max(0.0, min(1.0, strengthLevel)), 0.7)
    }

    private func stopLocked() {
        flushCarryIfNeeded()
        velocityX = 0
        velocityY = 0
        carryScaledX = 0
        carryScaledY = 0
        quietTicks = 0
        outputFlags = []
        lastTickTime = nil
        timer?.cancel()
        timer = nil
    }
}
