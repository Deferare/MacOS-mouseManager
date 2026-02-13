import Cocoa
import Foundation

final class ScrollSmoother {
    static let syntheticUserDataTag: Int64 = 0x4D4D4653 // "MMFS"

    private let queue = DispatchQueue(label: "mousemanager.scrollsmoother", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var isRunning: Bool = false
    private var lastTickTime: TimeInterval?

    // Remaining delta that we will distribute across several high-frequency timer frames.
    // This keeps a touch-like response while avoiding CVDisplayLink lifecycle edge cases.
    private var remainingX: Double = 0
    private var remainingY: Double = 0
    // Preserve sub-integer wheel movement so small deltas are not lost.
    private var carryScaledX: Double = 0
    private var carryScaledY: Double = 0

    private var continuous: Bool = true
    private var tuning = Tuning.defaultValue
    private var outputFlags: CGEventFlags = []
    private var smoothnessLevel: Double = 0.33
    private var quietTailTicks: Int = 0

    private let quietTailTicksToStop: Int = 8
    private let carryQuietThreshold: Double = 0.45

    private func clearBufferedMotion() {
        remainingX = 0
        remainingY = 0
        carryScaledX = 0
        carryScaledY = 0
        quietTailTicks = 0
    }

    private struct Tuning {
        let tauSeconds: Double
        let stopEpsilon: Double
        let outputScaleX: Double
        let outputScaleY: Double

        static let defaultValue = from(level: 0.33)

        static func from(level: Double) -> Tuning {
            let s = max(0.0, min(1.0, level))
            let tauSeconds = 0.070 + (0.185 * s)
            let stopEpsilon = 0.00085 - (0.00065 * s)
            let outputScale = 10.0 + (8.0 * s)
            return Tuning(
                tauSeconds: tauSeconds,
                stopEpsilon: max(0.00008, stopEpsilon),
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
            guard deltaX.isFinite, deltaY.isFinite else {
                self.clearBufferedMotion()
                self.stopIfNeeded()
                return
            }

            self.continuous = continuous
            if self.smoothnessLevel != smoothnessLevel {
                self.smoothnessLevel = smoothnessLevel
                self.tuning = Tuning.from(level: smoothnessLevel)
            }
            self.outputFlags = flags

            // Accumulate impulse to be smoothed out over subsequent frames.
            self.remainingX += deltaX
            self.remainingY += deltaY
            self.quietTailTicks = 0

            self.startIfNeeded()
        }
    }

    private func startIfNeeded() {
        if isRunning { return }
        isRunning = true
        lastTickTime = nil

        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(2))
        newTimer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = newTimer
        newTimer.resume()
    }

    private func stopIfNeeded() {
        guard isRunning else { return }
        isRunning = false
        lastTickTime = nil
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        // If Command is held (e.g. App Switcher), stop synthetic scroll immediately.
        if CGEventSource.flagsState(.hidSystemState).contains(.maskCommand) {
            clearBufferedMotion()
            stopIfNeeded()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let dtSeconds: Double
        if let lastTickTime {
            dtSeconds = max(1.0 / 240.0, min(1.0 / 30.0, now - lastTickTime))
        } else {
            dtSeconds = 1.0 / 120.0
        }
        lastTickTime = now

        // Smooth by distributing remaining delta with a 1st-order low-pass style step response.
        // alpha = 1 - exp(-dt/tau)  -> fraction to emit this frame.
        let alpha = 1.0 - exp(-dtSeconds / tuning.tauSeconds)

        let frameX = remainingX * alpha
        let frameY = remainingY * alpha
        remainingX -= frameX
        remainingY -= frameY

        let emitted = postSmoothedScroll(
            deltaX: frameX,
            deltaY: frameY,
            continuous: continuous,
            intScaleX: tuning.outputScaleX,
            intScaleY: tuning.outputScaleY
        )

        // Keep a short quiet tail so the end settles naturally instead of snapping.
        if abs(remainingX) < tuning.stopEpsilon && abs(remainingY) < tuning.stopEpsilon {
            remainingX = 0
            remainingY = 0
            if emitted {
                quietTailTicks = 0
            } else if abs(carryScaledX) < carryQuietThreshold && abs(carryScaledY) < carryQuietThreshold {
                quietTailTicks += 1
            } else {
                quietTailTicks = 0
            }

            if quietTailTicks >= quietTailTicksToStop {
                carryScaledX = 0
                carryScaledY = 0
                quietTailTicks = 0
                stopIfNeeded()
            }
        } else {
            quietTailTicks = 0
        }
    }

    private func postSmoothedScroll(deltaX: Double, deltaY: Double, continuous: Bool, intScaleX: Double, intScaleY: Double) -> Bool {
        carryScaledX += deltaX * intScaleX
        carryScaledY += deltaY * intScaleY

        let intX = Self.roundedInt32Clamped(carryScaledX)
        let intY = Self.roundedInt32Clamped(carryScaledY)
        if intX == 0 && intY == 0 {
            return false
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
        return true
    }

    static func postScroll(deltaX: Double, deltaY: Double, continuous: Bool, intScaleX: Double, intScaleY: Double, flags: CGEventFlags = []) {
        guard let source = SyntheticEventSource.hidSystemState else { return }

        // CGScrollWheelEventDeltaAxis1/2 is integer-based, but PointDeltaAxis is Double.
        // Use pixel units. Some apps rely more on integer deltas than PointDelta.
        let intY = roundedInt32Clamped(deltaY * intScaleY)
        let intX = roundedInt32Clamped(deltaX * intScaleX)
        if intX == 0 && intY == 0 {
            return
        }
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

    private static func roundedInt32Clamped(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        let minValue = Double(Int32.min)
        let maxValue = Double(Int32.max)
        if rounded <= minValue { return Int32.min }
        if rounded >= maxValue { return Int32.max }
        return Int32(rounded)
    }
}

