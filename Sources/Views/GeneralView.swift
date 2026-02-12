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

            Section("Permissions") {
                HStack(alignment: .firstTextBaseline) {
                    FormRowLabel(
                        "Accessibility",
                        subtitle: "To modify mouse/scroll behavior, macOS requires Accessibility permission."
                    )
                    Spacer()
                    Text(tapManager.accessibilityStatus.title)
                        .foregroundStyle(.secondary)
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
}

#Preview("GeneralView") {
    MainActor.assumeIsolated {
        PreviewHost.defaults {
            GeneralView()
                .frame(width: 720, height: 460)
        }
    }
}
