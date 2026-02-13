import SwiftUI

struct AboutView: View {
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
