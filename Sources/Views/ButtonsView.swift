import SwiftUI

struct ButtonsView: View {
    @EnvironmentObject private var settings: SettingsStore

    private struct AdditionalButtonSection: Identifiable {
        let title: String
        let actionKeyPath: ReferenceWritableKeyPath<SettingsStore, ButtonAction>
        var id: String { title }
    }

    private let additionalButtonSections: [AdditionalButtonSection] = [
        AdditionalButtonSection(title: "Button 4", actionKeyPath: \.button4ButtonAction),
        AdditionalButtonSection(title: "Button 5", actionKeyPath: \.button5ButtonAction)
    ]

    private let actions = ButtonAction.allCases

    private func actionBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, ButtonAction>) -> Binding<ButtonAction> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private func actionPicker(_ selection: Binding<ButtonAction>) -> some View {
        Picker("Click", selection: selection) {
            ForEach(actions, id: \.self) { action in
                Text(action.rawValue)
                    .tag(action)
            }
        }
    }

    var body: some View {
        Form {
            Section {
                actionPicker(actionBinding(\.middleClickButtonAction))

                Toggle(isOn: $settings.middleDragScrollingEnabled) {
                    FormRowLabel(
                        "Drag Touch",
                        subtitle: "Hold the middle button and drag to scroll as if you’re touching the content. A simple click still triggers your Middle Button action."
                    )
                }

                FormSliderRow(
                    "Inertia Strength",
                    subtitle: "How far content keeps moving after you release middle-button drag.",
                    value: $settings.middleDragInertiaStrength,
                    range: 0.0...1.0,
                    step: 0.01,
                    isEnabled: settings.middleDragScrollingEnabled
                ) { value in
                    "\(Int((value * 100).rounded()))%"
                }
            } header: {
                Label("Middle Button", systemImage: "computermouse.fill")
            }

            ForEach(additionalButtonSections) { section in
                Section {
                    actionPicker(actionBinding(section.actionKeyPath))
                } header: {
                    Label(section.title, systemImage: "button.programmable")
                }
            }
        }
    }
}

#Preview("ButtonsView") {
    MainActor.assumeIsolated {
        PreviewHost.defaults {
            ButtonsView()
                .frame(width: 720, height: 460)
        }
    }
}
