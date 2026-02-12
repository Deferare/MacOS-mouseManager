import SwiftUI

struct ButtonsView: View {
    @EnvironmentObject private var settings: SettingsStore

    private let actions = ButtonAction.allCases

    private func actionBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, ButtonAction>) -> Binding<ButtonAction> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        Form {
            Section("Middle Button") {
                Picker("Click", selection: actionBinding(\.middleClickButtonAction)) {
                    ForEach(actions, id: \.self) { action in
                        Text(action.rawValue)
                            .tag(action)
                    }
                }

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
            }

            Section("Button 4") {
                Picker("Click", selection: actionBinding(\.button4ButtonAction)) {
                    ForEach(actions, id: \.self) { action in
                        Text(action.rawValue)
                            .tag(action)
                    }
                }
            }

            Section("Button 5") {
                Picker("Click", selection: actionBinding(\.button5ButtonAction)) {
                    ForEach(actions, id: \.self) { action in
                        Text(action.rawValue)
                            .tag(action)
                    }
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
