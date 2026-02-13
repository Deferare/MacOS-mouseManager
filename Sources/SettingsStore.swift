import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    private enum Defaults {
        static let showInAppSwitcher: Bool = false
        static let smoothScrollingEnabled: Bool = false
        static let smoothnessLevel: Double = 0.68
        static let reverseDirection: Bool = false
        static let speedMultiplier: Double = 3.0
        static let middleDragScrollingEnabled: Bool = false
        static let middleDragInertiaStrength: Double = 0.62

        static let middleClickAction: String = "Look Up & Quick Look"
        static let button4ClickAction: String = "Back"
        static let button5ClickAction: String = "Forward"
    }

    private var isBatchUpdating = false
    private var hasPendingChangeInBatch = false

    private func notifyIfChanged<T: Equatable>(_ oldValue: T, _ newValue: T) {
        guard oldValue != newValue else { return }
        if isBatchUpdating {
            hasPendingChangeInBatch = true
        } else {
            objectWillChange.send()
        }
    }

    private func performBatchUpdate(_ updates: () -> Void) {
        guard !isBatchUpdating else {
            updates()
            return
        }
        isBatchUpdating = true
        hasPendingChangeInBatch = false
        updates()
        isBatchUpdating = false
        if hasPendingChangeInBatch {
            objectWillChange.send()
        }
    }

    // General
    @AppStorage("enabled") var enabled: Bool = false { didSet { notifyIfChanged(oldValue, enabled) } }
    @AppStorage("showInAppSwitcher") var showInAppSwitcher: Bool = Defaults.showInAppSwitcher { didSet { notifyIfChanged(oldValue, showInAppSwitcher) } }
    @AppStorage("didInitializeDefaults") var didInitializeDefaults: Bool = false { didSet { notifyIfChanged(oldValue, didInitializeDefaults) } }

    // Scrolling
    @AppStorage("reverseDirection") var reverseDirection: Bool = Defaults.reverseDirection { didSet { notifyIfChanged(oldValue, reverseDirection) } }
    // multiplier applied to scroll deltas
    @AppStorage("speedMultiplier") var speedMultiplier: Double = Defaults.speedMultiplier { didSet { notifyIfChanged(oldValue, speedMultiplier) } }
    @AppStorage("smoothScrollingEnabled") var smoothScrollingEnabled: Bool = Defaults.smoothScrollingEnabled { didSet { notifyIfChanged(oldValue, smoothScrollingEnabled) } }
    @AppStorage("smoothnessLevel") var smoothnessLevel: Double = Defaults.smoothnessLevel { didSet { notifyIfChanged(oldValue, smoothnessLevel) } }
    @AppStorage("middleDragScrollingEnabled") var middleDragScrollingEnabled: Bool = Defaults.middleDragScrollingEnabled { didSet { notifyIfChanged(oldValue, middleDragScrollingEnabled) } }
    @AppStorage("middleDragInertiaStrength") var middleDragInertiaStrength: Double = Defaults.middleDragInertiaStrength { didSet { notifyIfChanged(oldValue, middleDragInertiaStrength) } }

    // Buttons (placeholder mappings)
    @AppStorage("middleClickAction") var middleClickAction: String = Defaults.middleClickAction { didSet { notifyIfChanged(oldValue, middleClickAction) } }
    @AppStorage("button4ClickAction") var button4ClickAction: String = Defaults.button4ClickAction { didSet { notifyIfChanged(oldValue, button4ClickAction) } }
    @AppStorage("button5ClickAction") var button5ClickAction: String = Defaults.button5ClickAction { didSet { notifyIfChanged(oldValue, button5ClickAction) } }

    var middleClickButtonAction: ButtonAction {
        get { decodeButtonAction(middleClickAction) }
        set { middleClickAction = newValue.rawValue }
    }

    var button4ButtonAction: ButtonAction {
        get { decodeButtonAction(button4ClickAction) }
        set { button4ClickAction = newValue.rawValue }
    }

    var button5ButtonAction: ButtonAction {
        get { decodeButtonAction(button5ClickAction) }
        set { button5ClickAction = newValue.rawValue }
    }

    private func applyScrollingDefaultsValues() {
        smoothScrollingEnabled = true
        smoothnessLevel = Defaults.smoothnessLevel
        reverseDirection = Defaults.reverseDirection
        speedMultiplier = Defaults.speedMultiplier
    }

    private func applyButtonsDefaultsValues() {
        middleClickAction = Defaults.middleClickAction
        middleDragScrollingEnabled = true
        middleDragInertiaStrength = Defaults.middleDragInertiaStrength
        button4ClickAction = Defaults.button4ClickAction
        button5ClickAction = Defaults.button5ClickAction
    }

    func restoreScrollingDefaults() {
        performBatchUpdate {
            applyScrollingDefaultsValues()
        }
    }

    func restoreButtonsDefaults() {
        performBatchUpdate {
            applyButtonsDefaultsValues()
        }
    }

    func applyDefaultSettings() {
        performBatchUpdate {
            applyScrollingDefaultsValues()
            applyButtonsDefaultsValues()
        }
    }

    var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            enabled: enabled,
            smoothScrollingEnabled: smoothScrollingEnabled,
            smoothnessLevel: smoothnessLevel,
            middleDragScrollingEnabled: middleDragScrollingEnabled,
            middleDragInertiaStrength: middleDragInertiaStrength,
            reverseDirection: reverseDirection,
            speedMultiplier: speedMultiplier,
            middleClickAction: middleClickAction,
            button4ClickAction: button4ClickAction,
            button5ClickAction: button5ClickAction
        )
    }

    private func decodeButtonAction(_ rawValue: String) -> ButtonAction {
        ButtonAction(rawValue: rawValue) ?? .none
    }
}

struct SettingsSnapshot: Equatable {
    let enabled: Bool
    let smoothScrollingEnabled: Bool
    let smoothnessLevel: Double
    let middleDragScrollingEnabled: Bool
    let middleDragInertiaStrength: Double
    let reverseDirection: Bool
    let speedMultiplier: Double
    let middleClickAction: String
    let button4ClickAction: String
    let button5ClickAction: String

    var middleClickButtonAction: ButtonAction {
        ButtonAction(rawValue: middleClickAction) ?? .none
    }

    var button4ButtonAction: ButtonAction {
        ButtonAction(rawValue: button4ClickAction) ?? .none
    }

    var button5ButtonAction: ButtonAction {
        ButtonAction(rawValue: button5ClickAction) ?? .none
    }
}

enum SliderValueAdapter {
    static func snapped(
        _ source: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> Binding<Double> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                let snapped = (clamped / step).rounded() * step
                if source.wrappedValue != snapped {
                    source.wrappedValue = snapped
                }
            }
        )
    }
}
