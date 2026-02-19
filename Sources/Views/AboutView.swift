import SwiftUI

struct AboutView: View {
    private let supportEmail = "deferare@icloud.com"
    private let repositoryURL = URL(string: "https://github.com/Deferare/MacOS-mouseManager")!
    private let sponsorsURL = URL(string: "https://github.com/sponsors/Deferare")!

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
                    "Open Source",
                    subtitle: "Mouse Manager is open-source and maintained on GitHub."
                )
                Link(destination: repositoryURL) {
                    Label("View Repository", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                FormRowLabel(
                    "Support Email",
                    subtitle: "\(supportEmail) (subject: [MouseManager Preview])"
                )
            }

            Section("Support") {
                VStack(alignment: .leading, spacing: 12) {
                    FormRowLabel(
                        "Support Mouse Manager",
                        subtitle: "If this app helps your workflow, you can support ongoing open-source development via GitHub Sponsors."
                    )
                    Link(destination: sponsorsURL) {
                        Label("Sponsor on GitHub", systemImage: "heart.fill")
                    }
                    .buttonStyle(.link)
                    FormHelpText(
                        text: "Opens github.com/sponsors/Deferare in your default browser.",
                        leadingPadding: 0
                    )
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
