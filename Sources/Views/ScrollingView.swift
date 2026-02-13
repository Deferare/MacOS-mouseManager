import Foundation
import SwiftUI

struct ScrollingView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.smoothScrollingEnabled) {
                    FormRowLabel(
                        "Smooth Scrolling",
                        subtitle: "When enabled, scroll is sent as continuous (trackpad-like) scrolling and smoothed."
                    )
                }

                FormSliderRow(
                    "Smoothness",
                    subtitle: "Higher values feel softer and longer; lower values feel tighter.",
                    value: $settings.smoothnessLevel,
                    range: 0.0...1.0,
                    step: 0.01,
                    isEnabled: settings.smoothScrollingEnabled
                ) { value in
                    "\(Int((value * 100).rounded()))%"
                }
                Toggle("Reverse Direction", isOn: $settings.reverseDirection)
            } header: {
                Text("Wheel")
            }

            Section {
                FormSliderRow(
                    "Multiplier",
                    subtitle: "Applies to both vertical and horizontal scroll.",
                    value: $settings.speedMultiplier,
                    range: 0.5...10.0,
                    step: 0.01
                ) { value in
                    String(format: "%.2f×", value)
                }
            } header: {
                Text("Speed")
            }
        }
    }
}

#Preview("ScrollingView") {
    MainActor.assumeIsolated {
        PreviewHost.defaults {
            ScrollingView()
                .frame(width: 720, height: 460)
        }
    }
}
