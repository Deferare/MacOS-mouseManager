import SwiftUI

struct AboutView: View {
    private let sponsorURL = URL(string: "https://github.com/sponsors/deferare")
    private let supportEmail = "deferare@icloud.com"

    var body: some View {
        Form {
            Section {
                FormRowLabel(
                    "Mouse Manager",
                    subtitle: "Public Preview for macOS 26+ focused on mouse buttons and smooth scrolling."
                )
                FormRowLabel(
                    "Notes",
                    subtitle: "This build is distributed as a Public Preview. First launch may require right-click Open and Open Anyway in Privacy & Security."
                )
                FormRowLabel(
                    "Permissions",
                    subtitle: "Mouse and scroll interception features require Accessibility permission."
                )
                FormRowLabel(
                    "Updates",
                    subtitle: "Updates are manual. Install the latest GitHub Release ZIP and replace the app in /Applications."
                )
                FormRowLabel(
                    "Support Email",
                    subtitle: "\(supportEmail) (subject: [MouseManager Preview])"
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
