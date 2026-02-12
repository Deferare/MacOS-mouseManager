import SwiftUI

struct FormSliderRow: View {
    private let title: String
    private let subtitle: String?
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let isEnabled: Bool
    private let valueText: (Double) -> String

    init(
        _ title: String,
        subtitle: String? = nil,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 0.01,
        isEnabled: Bool = true,
        valueText: @escaping (Double) -> String
    ) {
        self.title = title
        self.subtitle = subtitle
        _value = value
        self.range = range
        self.step = step
        self.isEnabled = isEnabled
        self.valueText = valueText
    }

    var body: some View {
        LabeledContent {
            HStack(alignment: .center) {
                Slider(
                    value: SliderValueAdapter.snapped(
                        $value,
                        range: range,
                        step: step
                    ),
                    in: range
                )
                .frame(maxWidth: .infinity)
                .disabled(!isEnabled)

                Text(valueText(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[VerticalAlignment.center]
            }
        } label: {
            FormRowLabel(
                title,
                subtitle: subtitle
            )
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[VerticalAlignment.center]
            }
        }
    }
}
