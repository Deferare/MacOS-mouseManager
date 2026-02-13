import AppKit
import SwiftUI

struct GeneralView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var tapManager: EventTapManager

    var body: some View {
        Form {
            Section("Mouse Manager") {
                Toggle(isOn: $settings.enabled) {
                    FormRowLabel(
                        "Enable Mouse Manager",
                        subtitle: "Mouse Manager stays enabled after you quit the app."
                    )
                }
                .toggleStyle(.switch)
                .onChange(of: settings.enabled) { newValue in
                    guard newValue else { return }

                    // Prompt for Accessibility permission right away (macOS will show the system dialog).
                    tapManager.requestAccessibilityPermission()
                }
            }

            Section("App") {
                Toggle(isOn: $settings.showInAppSwitcher) {
                    FormRowLabel(
                        "Show in Cmd+Tab and Dock",
                        subtitle: "Turn off to run as a background app (hidden from Cmd+Tab and Dock), like the current behavior."
                    )
                }
                .toggleStyle(.switch)

                HStack(alignment: .firstTextBaseline) {
                    FormRowLabel(
                        "Quit App",
                        subtitle: "Mouse Manager will stop until you launch it again."
                    )
                    Spacer()
                    Button("Quit Now") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }

            Section("Permissions") {
                HStack(alignment: .firstTextBaseline) {
                    FormRowLabel(
                        "Accessibility",
                        subtitle: "To modify mouse/scroll behavior, macOS requires Accessibility permission."
                    )
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: tapManager.accessibilityStatus.icon)
                        Text(tapManager.accessibilityStatus.title)
                    }
                    .foregroundStyle(tapManager.accessibilityStatus.color)
                    
                    Button("Request…") { tapManager.requestAccessibilityPermission(forceOpenSettings: true) }
                }
            }
        }
    }
}

private extension AccessibilityStatus {
    var title: String {
        switch self {
        case .unknown: return "Unknown"
        case .granted: return "Granted"
        case .denied: return "Not granted"
        }
    }

    var icon: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .denied, .unknown: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .granted: return .green
        case .denied, .unknown: return .orange
        }
    }
}

#Preview("GeneralView") {
    MainActor.assumeIsolated {
        PreviewHost.defaults {
            GeneralView()
                .frame(width: 720, height: 460)
        }
    }
}
