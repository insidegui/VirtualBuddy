import SwiftUI
import Combine
import VirtualCore

struct NumericValueField<Value: BinaryInteger, F: Formatter>: View {

    var label: String
    @Binding var value: Value
    var range: ClosedRange<Value>
    var formatter: F

    @Environment(\.unfocusActiveField)
    private var unfocus

    init(label: String, value: Binding<Value>, range: ClosedRange<Value>, formatter: F) {
        self.label = label
        self._value = value
        self.range = range
        self.formatter = formatter
    }

    @FocusState
    private var isFocused: Bool

    @State private var isInEditMode = false

    var body: some View {
        EphemeralTextField($value) { currentValue in
            Text(formatter.string(for: currentValue) ?? "")
        } editableContent: { binding in
            TextField(label, value: binding, formatter: formatter)
        } clamp: { $0.limited(to: range) }
            .multilineTextAlignment(.trailing)
    }
}

extension BinaryInteger {
    func limited(to range: ClosedRange<Self>) -> Self {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

#if DEBUG

struct NumericValueField_Previews: PreviewProvider {
    static var previews: some View {
        _Template()
    }

    struct _Template: View {
        @State var value = 1
        
        @Environment(\.unfocusActiveField)
        private var unfocusActiveField

        private let formatter: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            f.minimumFractionDigits = 0
            f.hasThousandSeparators = false
            return f
        }()

        var body: some View {
            VStack {
                NumericValueField(
                    label: "Test",
                    value: $value,
                    range: 1...10,
                    formatter: formatter
                )

                Button("Unfocus") {
                    unfocusActiveField.send()
                }
                .controlSize(.small)
            }
            .padding()
        }
    }
}

#endif
