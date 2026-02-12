import SwiftUI

struct FormHelpText: View {
    let text: String
    var leadingPadding: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingPadding)
    }
}

#Preview("FormHelpText") {
    Form {
        Section("Preview") {
            Toggle("Example Toggle", isOn: .constant(true))
            FormHelpText(text: "This is helper text that aligns under a toggle label.")
            FormHelpText(text: "This is helper text aligned to the section content edge.", leadingPadding: 0)
        }
    }
    .formStyle(.grouped)
    .frame(width: 720, height: 460)
}
