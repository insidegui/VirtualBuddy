import SwiftUI
import Combine
import VirtualCore

struct NumericPropertyControl<Value: BinaryInteger, F: Formatter>: View {
    @Binding var value: Value
    var range: ClosedRange<Value>
    var step: Value? = nil
    var hideSlider = false
    var label: String
    var formatter: F
    var unfocus = VoidSubject()
    var spacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack {
                Text(label)
                    .foregroundColor(.white.opacity(0.7))
                    .blendMode(.plusLighter)

                Spacer()

                NumericValueField(
                    label: label,
                    value: $value,
                    range: range,
                    formatter: formatter,
                    unfocus: unfocus
                )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(minWidth: 30)
            }

            if !hideSlider {
                Group {
                    if let step {
                        Slider(value: $value.sliderValue, in: range.sliderRange, step: Double(step), onEditingChanged: sliderEditingChanged)
                    } else {
                        Slider(value: $value.sliderValue, in: range.sliderRange, onEditingChanged: sliderEditingChanged)
                    }
                }
                .controlSize(.mini)
            }
        }
        .transition(.asymmetric(insertion: .offset(x: 0, y: -40), removal: .offset(x: 0, y: 40)).combined(with: .opacity))
    }
    
    private func sliderEditingChanged(_ isEditing: Bool) {
        guard isEditing else { return }
        unfocus.send()
    }
}

extension NumberFormatter {
    static let numericPropertyControlDefault: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        f.hasThousandSeparators = false
        return f
    }()
}

#if DEBUG
struct PropertySlider_Previews: PreviewProvider {
    static var previews: some View {
        _Template()
    }

    struct _Template: View {
        @State private var value = 1

        var body: some View {
            NumericPropertyControl(value: $value, range: 0...10, step: 1, hideSlider: false, label: "Preview", formatter: NumberFormatter.numericPropertyControlDefault)
                .padding()
                .frame(maxWidth: 200)
        }
    }
}
#endif
