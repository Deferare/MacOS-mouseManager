import SwiftUI

struct FormRowLabel: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("FormRowLabel") {
    Form {
        Section("Preview") {
            Toggle(isOn: .constant(true)) {
                FormRowLabel("Use pointer cursors", subtitle: "Change the cursor to a pointer when hovering over interactive elements")
            }
            Toggle(isOn: .constant(false)) {
                FormRowLabel("Use opaque window background", subtitle: "Make windows use a solid background rather than system translucency")
            }
        }
    }
    .formStyle(.grouped)
    .frame(width: 760, height: 520)
}

