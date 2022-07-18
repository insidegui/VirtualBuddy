import SwiftUI
import Combine
import VirtualCore

struct NumericValueField<Value: BinaryInteger, F: Formatter>: View {

    var label: String
    @Binding var value: Value
    var range: ClosedRange<Value>
    var formatter: F

    @State private var internalValue: Value

    private let unfocus: VoidSubject

    init(label: String, value: Binding<Value>, range: ClosedRange<Value>, formatter: F, unfocus: VoidSubject? = nil) {
        self.label = label
        self._value = value
        self.range = range
        self.formatter = formatter
        self._internalValue = .init(initialValue: value.wrappedValue)
        self.unfocus = unfocus ?? VoidSubject()
    }

    @FocusState
    private var isFocused: Bool

    @State private var isInEditMode = false

    var body: some View {
        Group {
            if isInEditMode {
                editableBody
                    .onChange(of: isFocused) { newValue in
                        if !newValue { isInEditMode = false }
                    }
            } else {
                Text(formatter.string(for: value) ?? "")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture { isInEditMode = true }
            }
        }
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .onChange(of: isInEditMode) { newValue in
            if newValue { isFocused = true }
        }
        .onChange(of: value) { newValue in
            internalValue = newValue
        }
    }

    private var editableBody: some View {
        TextField(label, value: $internalValue, formatter: formatter)
            .focused($isFocused)
            .textFieldStyle(.plain)
            .onChange(of: value) { newValue in
                // Unfocus when changing the value externally.
                isFocused = false
                internalValue = newValue
            }
            .onSubmit {
                /// Update the external value with the edited value on submit,
                /// limiting to the allowed range.
                value = internalValue.limited(to: range)
                internalValue = internalValue.limited(to: range)

                isFocused = false
            }
            .onExitCommand {
                /// Unfocus the field when pressing the escape key.
                isFocused = false
                /// Restore initial value when cancelling out of the field.
                internalValue = value
            }
            .onReceive(unfocus) {
                isFocused = false
            }
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

        var unfocus = VoidSubject()

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
                    formatter: formatter,
                    unfocus: unfocus
                )

                Button("Unfocus") {
                    unfocus.send()
                }
                .controlSize(.small)
            }
            .padding()
        }
    }
}

#endif
