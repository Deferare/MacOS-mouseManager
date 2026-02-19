import AppKit
import SwiftUI

struct AboutView: View {
    private let supportEmail = "deferare@icloud.com"
    private let repositoryURL = URL(string: "https://github.com/Deferare/MacOS-mouseManager")!
    private let releaseURL = URL(string: "https://github.com/Deferare/MacOS-mouseManager/releases")!
    private let issuesURL = URL(string: "https://github.com/Deferare/MacOS-mouseManager/issues")!
    private let sponsorsURL = URL(string: "https://github.com/sponsors/Deferare")!

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                    .padding(.top, 56)

                cardContainer {
                    Group {
                        aboutSection(title: "Developer", value: "JiHoon K (Deferare)")
                        Divider()
                        aboutSection(title: "Contact", value: supportEmail, destination: supportEmailURL)
                        Divider()
                        aboutSection(
                            title: "Repository",
                            value: "github.com/Deferare/MacOS-mouseManager",
                            destination: repositoryURL
                        )
                        Divider()
                        aboutSection(title: "License", value: "© 2026 Deferare. All rights reserved.")
                    }

                    Divider()

                    Text("Preview Notes")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Public Preview build for macOS 26+.", systemImage: "sparkles")
                        Label(
                            "First launch may require right-click Open and Open Anyway in Privacy & Security.",
                            systemImage: "lock.shield"
                        )
                        Label(
                            "Mouse and scroll interception features require Accessibility permission.",
                            systemImage: "hand.tap"
                        )
                        Label("Updates are manual via the latest GitHub Release ZIP.", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                cardContainer {
                    Text("Support Development")
                        .font(.headline)

                    Text(
                        "If Mouse Manager helps your workflow, you can support ongoing open-source development or share feedback."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Link(destination: sponsorsURL) {
                            Label("Sponsor on GitHub", systemImage: "heart.fill")
                        }
                        .buttonStyle(.link)

                        Link(destination: issuesURL) {
                            Label("Report Issue / Request Feature", systemImage: "exclamationmark.bubble")
                        }
                        .buttonStyle(.link)

                        Link(destination: releaseURL) {
                            Label("View Releases", systemImage: "shippingbox")
                        }
                        .buttonStyle(.link)
                    }
                }

                Text("Built with SwiftUI")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            appIconImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 136, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)

            VStack(spacing: 8) {
                Text("Mouse Manager")
                    .font(.system(size: 34, weight: .black))

                Text(appVersionText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func aboutSection(title: String, value: String, destination: URL? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let destination {
                Link(value, destination: destination)
                    .font(.body.weight(.medium))
            } else {
                Text(value)
                    .font(.body.weight(.medium))
            }
        }
    }

    private var supportEmailURL: URL {
        URL(string: "mailto:\(supportEmail)")!
    }

    private var appVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        if let shortVersion, !shortVersion.isEmpty {
            return "Version \(shortVersion)"
        }
        return "Version"
    }

    private var appIconImage: Image {
        if let image = NSImage(named: "AppIcon") {
            return Image(nsImage: image)
        }
        if let image = NSImage(named: NSImage.applicationIconName) {
            return Image(nsImage: image)
        }
        return Image(systemName: "cursorarrow.click.2")
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
