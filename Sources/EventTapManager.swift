import Cocoa
import Foundation

enum AccessibilityStatus: Equatable {
    case unknown
    case granted
    case denied
}

enum ButtonAction: String, CaseIterable {
    case none = "None"
    case back = "Back"
    case forward = "Forward"
    case missionControl = "Mission Control"
    case appExpose = "App Exposé"
    case lookUpQuickLook = "Look Up & Quick Look"
}

@MainActor
final class EventTapManager: ObservableObject {
    @Published private(set) var accessibilityStatus: AccessibilityStatus = .unknown

    private static let trustPollInterval: TimeInterval = 0.5
    private static let permissionGrantPollTimeout: TimeInterval = 45.0
    private static func eventMask(for settings: SettingsSnapshot) -> CGEventMask {
        var mask: CGEventMask =
            (1 << CGEventType.scrollWheel.rawValue)

        let hasButtonActions =
            settings.middleClickButtonAction != .none ||
            settings.button4ButtonAction != .none ||
            settings.button5ButtonAction != .none

        if settings.middleDragScrollingEnabled || hasButtonActions {
            mask |=
                (1 << CGEventType.otherMouseDown.rawValue) |
                (1 << CGEventType.otherMouseUp.rawValue)
        }

        if settings.middleDragScrollingEnabled {
            // Some devices do not emit otherMouseDragged while the middle button is held,
            // so we also listen for mouseMoved to keep drag scrolling responsive.
            mask |=
                (1 << CGEventType.otherMouseDragged.rawValue) |
                (1 << CGEventType.mouseMoved.rawValue)
        }

        return mask
    }

    private let tapRunLoopHost = EventTapRunLoopHost()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeEventMask: CGEventMask?
    private var tapContext: SharedTapContext?
    private var lastSettingsSnapshot: SettingsSnapshot?
    private var trustPollTimer: Timer?
    private var isAwaitingAccessibilityGrant: Bool = false
    private var awaitingAccessibilityGrantDeadline: TimeInterval?
    private weak var settingsStore: SettingsStore?
    private var workspaceObserverTokens: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        let didWakeToken = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.recoverEventPipelineAfterWake()
            }
        }
        workspaceObserverTokens = [didWakeToken]
    }

    func apply(settings: SettingsStore) {
        settingsStore = settings
        let snapshot = settings.snapshot
        let previousSnapshot = lastSettingsSnapshot
        let previousEnabled = previousSnapshot?.enabled
        let settingsChanged = previousSnapshot != snapshot
        lastSettingsSnapshot = snapshot

        // Avoid AX trust checks for every slider tick while enabled. Refresh on first
        // launch, enable-state changes, and whenever interception is currently disabled.
        if accessibilityStatus == .unknown || previousEnabled != snapshot.enabled || !snapshot.enabled {
            let previousStatus = accessibilityStatus
            updateAccessibilityStatus()
            handleAccessibilityTransition(previousStatus: previousStatus, settings: settings)
        }
        updateTrustPollingState()

        guard snapshot.enabled else {
            stop()
            return
        }

        guard accessibilityStatus == .granted else {
            stop()
            return
        }

        let desiredEventMask = Self.eventMask(for: snapshot)
        if eventTap != nil, activeEventMask != desiredEventMask {
            // Avoid paying the callback cost for high-frequency event classes when the
            // current settings don't require them (notably mouseMoved).
            stop()
        }

        if settingsChanged, let tapContext {
            tapContext.updateSettings(snapshot)
        }
        if !startIfNeeded(settings: snapshot, eventMask: desiredEventMask) {
            // If event tap creation fails, permission state is effectively unusable.
            handleTapStartFailure(using: settings)
            updateTrustPollingState()
        }
    }

    func requestAccessibilityPermission(forceOpenSettings: Bool = false) {
        isAwaitingAccessibilityGrant = true
        awaitingAccessibilityGrantDeadline =
            ProcessInfo.processInfo.systemUptime + Self.permissionGrantPollTimeout
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
        pollAccessibilityTrust()
        if forceOpenSettings {
            openAccessibilitySettings()
        }
    }

    private func updateAccessibilityStatus() {
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
    }

    private func disableSettingsIfEnabled(_ settings: SettingsStore) {
        guard settings.enabled else { return }
        settings.enabled = false
        lastSettingsSnapshot = settings.snapshot
    }

    private func handleTapStartFailure(using settings: SettingsStore) {
        accessibilityStatus = .denied
        disableSettingsIfEnabled(settings)
    }

    private func handleAccessibilityTransition(previousStatus: AccessibilityStatus, settings: SettingsStore) {
        let isGranted = (accessibilityStatus == .granted)
        tapContext?.setInterceptionEnabled(settings.enabled && isGranted)

        if previousStatus == .granted, !isGranted {
            stop()
            disableSettingsIfEnabled(settings)
            return
        }

        if previousStatus != .granted, isGranted {
            isAwaitingAccessibilityGrant = false
            awaitingAccessibilityGrantDeadline = nil
        }
    }

    private func shouldPollAccessibilityTrust() -> Bool {
        if
            isAwaitingAccessibilityGrant,
            let deadline = awaitingAccessibilityGrantDeadline,
            ProcessInfo.processInfo.systemUptime >= deadline
        {
            isAwaitingAccessibilityGrant = false
            awaitingAccessibilityGrantDeadline = nil
        }
        let enabled = settingsStore?.enabled ?? false
        return enabled || isAwaitingAccessibilityGrant
    }

    private func updateTrustPollingState() {
        if shouldPollAccessibilityTrust() {
            startTrustPollingIfNeeded()
        } else {
            stopTrustPolling()
        }
    }

    private func startTrustPollingIfNeeded() {
        if trustPollTimer != nil { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.trustPollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.pollAccessibilityTrust()
            }
        }
        timer.tolerance = Self.trustPollInterval * 0.4
        trustPollTimer = timer
    }

    private func stopTrustPolling() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil
    }

    private func pollAccessibilityTrust() {
        guard let settingsStore else {
            stopTrustPolling()
            return
        }

        let previousStatus = accessibilityStatus
        updateAccessibilityStatus()
        let isGranted = (accessibilityStatus == .granted)
        handleAccessibilityTransition(previousStatus: previousStatus, settings: settingsStore)

        if previousStatus != .granted, isGranted, let snapshot = lastSettingsSnapshot, snapshot.enabled {
            if let tapContext {
                tapContext.updateSettings(snapshot)
            }
            let desiredEventMask = Self.eventMask(for: snapshot)
            if !startIfNeeded(settings: snapshot, eventMask: desiredEventMask) {
                handleTapStartFailure(using: settingsStore)
            }
        }
        updateTrustPollingState()
    }

    deinit {
        trustPollTimer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceObserverTokens {
            center.removeObserver(token)
        }
        workspaceObserverTokens.removeAll()
    }

    private func recoverEventPipelineAfterWake() {
        guard let settingsStore else { return }
        // Sleep/wake can leave the wheel smoothing pipeline stale on some setups.
        // Recreating the tap/context is cheap and restores wheel delivery deterministically.
        stop()
        apply(settings: settingsStore)
    }

    private func startIfNeeded(settings: SettingsSnapshot, eventMask: CGEventMask) -> Bool {
        if eventTap != nil { return true }

        let context = SharedTapContext(settings: settings)
        context.setInterceptionEnabled(true)
        tapContext = context
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let context = Unmanaged<SharedTapContext>.fromOpaque(userInfo).takeUnretainedValue()
            return context.handle(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            tapContext = nil
            activeEventMask = nil
            return false
        }
        context.attachEventTap(tap)

        eventTap = tap
        activeEventMask = eventMask
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            tapRunLoopHost.addSource(runLoopSource)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func stop() {
        tapContext?.setInterceptionEnabled(false)

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            tapRunLoopHost.removeSource(runLoopSource)
        }
        runLoopSource = nil
        eventTap = nil
        activeEventMask = nil
        tapContext = nil
    }
}
