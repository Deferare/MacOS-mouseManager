import Cocoa
import Foundation

final class MiddleDragMomentumAnimator {
    private let queue = DispatchQueue(label: "mousemanager.middledragmomentum", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var velocityX: Double = 0
    private var velocityY: Double = 0
    private var carryScaledX: Double = 0
    private var carryScaledY: Double = 0
    private var outputFlags: CGEventFlags = []
    private var strengthLevel: Double = 0.5
    private var strengthResponse: Double = pow(0.5, 0.7)
    private var lastTickTime: TimeInterval?
    private var startTime: TimeInterval?
    private var launchSpeed: Double = 0
    private var quietTicks: Int = 0

    private static let minimumDtSeconds: Double = 1.0 / 240.0
    private static let maximumDtSeconds: Double = 1.0 / 30.0
    private let momentumOutputScaleX: Double = 34.0
    private let momentumOutputScaleY: Double = 38.0
    private let quietTicksToStop: Int = 20
    private let minimumLaunchSpeed: Double = 20.0
    private let minimumActiveSpeed: Double = 0.75
    private let maxLaunchSpeed: Double = 7_200.0
    private let decelerationReferenceSpeed: Double = 2_300.0
    private let easeInDurationSeconds: Double = 0.10
    private let easeOutStartNormalizedSpeed: Double = 0.34
    private let introMinGain: Double = 0.74
    private let tailMinGain: Double = 0.78

    func updateStrength(level: Double) {
        queue.async {
            self.strengthLevel = max(0.0, min(1.0, level))
            self.strengthResponse = pow(self.strengthLevel, 0.7)
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
            self.launchSpeed = speed
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
        startTime = nil
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
        if startTime == nil {
            startTime = now
        }
        let frameShapingGain = momentumFrameShapingGain(now: now, speed: speed)
        let frameX = velocityX * dtSeconds * frameShapingGain
        let frameY = velocityY * dtSeconds * frameShapingGain
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

    private var launchScale: Double {
        // Keep release speed close to drag velocity for a stronger touch-like handoff.
        0.50 + (0.98 * strengthResponse)
    }

    private func decelerationRatePerMillisecond(forSpeed speed: Double) -> Double {
        // Blend between low-speed and high-speed decay rates.
        // Near zero: stronger braking to avoid a long "crawl".
        // High speed: gentler braking for a richer glide.
        let normalized = min(1.0, max(0.0, speed / decelerationReferenceSpeed))
        let curve = pow(normalized, 0.52)
        let lowSpeedRate = 0.9938 + (0.0018 * strengthResponse)
        let highSpeedRate = 0.9975 + (0.0017 * strengthResponse)
        return lowSpeedRate + ((highSpeedRate - lowSpeedRate) * curve)
    }

    private func momentumFrameShapingGain(now: TimeInterval, speed: Double) -> Double {
        let elapsed = max(0.0, now - (startTime ?? now))
        let easeInProgress = min(1.0, max(0.0, elapsed / easeInDurationSeconds))
        let easeInGain = introMinGain + ((1.0 - introMinGain) * smoothstep(easeInProgress))

        let normalizedSpeed = min(1.0, max(0.0, speed / max(launchSpeed, 0.000_1)))
        let easeOutProgress = min(1.0, max(0.0, (easeOutStartNormalizedSpeed - normalizedSpeed) / easeOutStartNormalizedSpeed))
        let easeOutGain = 1.0 - ((1.0 - tailMinGain) * smoothstep(easeOutProgress))

        return easeInGain * easeOutGain
    }

    private func smoothstep(_ t: Double) -> Double {
        t * t * (3.0 - (2.0 * t))
    }

    private func stopLocked() {
        velocityX = 0
        velocityY = 0
        carryScaledX = 0
        carryScaledY = 0
        launchSpeed = 0
        quietTicks = 0
        outputFlags = []
        lastTickTime = nil
        startTime = nil
        timer?.cancel()
        timer = nil
    }
}
