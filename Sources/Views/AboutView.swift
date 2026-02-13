import SwiftUI

struct AboutView: View {
    private let sponsorURL = URL(string: "https://github.com/sponsors/deferare")

    var body: some View {
        Form {
            Section {
                FormRowLabel(
                    "Mouse Manager",
                    subtitle: "A lightweight macOS utility for mouse buttons and smooth scrolling."
                )
                FormRowLabel(
                    "Notes",
                    subtitle: "This is a starter project. Button remapping and scroll smoothing require Accessibility permission and more advanced event processing."
                )
            }

            Section("Support") {
                HStack(alignment: .center) {
                    FormRowLabel(
                        "Support Mouse Manager",
                        subtitle: "If this app helps your workflow, you can support future development."
                    )
                    Spacer()

                    if let sponsorURL {
                        Link(destination: sponsorURL) {
                            Label("Sponsor", systemImage: "heart.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

#Preview("AboutView") {
    MainActor.assumeIsolated {
        PreviewHost.defaults {
            AboutView()
                .frame(width: 720, height: 460)
        }
    }
}
