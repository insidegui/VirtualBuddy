//
//  EphemeralTextField.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

private struct EphemeralTextFieldContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct EphemeralTextField<Value, StaticContent, EditableContent>: View where StaticContent: View, EditableContent: View, Value: Equatable {
    
    @Binding var value: Value
    var staticContent: (Value) -> StaticContent
    var editableContent: (Binding<Value>) -> EditableContent
    var clamp: (Value) -> Value
    var validate: (Value) -> Bool
    var alignment: Alignment
    var setFocus: BoolSubject
    
    init(_ value: Binding<Value>,
         alignment: Alignment = .trailing,
         setFocus: BoolSubject = .init(),
         @ViewBuilder staticContent: @escaping (Value) -> StaticContent,
         @ViewBuilder editableContent: @escaping (Binding<Value>) -> EditableContent,
         clamp: @escaping (Value) -> Value = { $0 },
         validate: @escaping (Value) -> Bool = { _ in  true })
    {
        self._value = value
        self._internalValue = .init(wrappedValue: value.wrappedValue)
        self.alignment = alignment
        self.setFocus = setFocus
        self.staticContent = staticContent
        self.editableContent = editableContent
        self.clamp = clamp
        self.validate = validate
    }
    
    @State private var internalValue: Value
    
    @Environment(\.isEnabled) private var isEnabled
    
    @Environment(\.unfocusActiveField)
    private var unfocus
    
    @FocusState
    private var isFocused: Bool

    @State private var isInEditMode = false
    
    @State private var contentWidth: CGFloat = 40
    
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        ZStack {
            staticContent(internalValue)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    beginEditing()
                }
                .onHover { isHovered = $0 }
                .opacity(isInEditMode ? 0 : 1)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: EphemeralTextFieldContentWidthKey.self, value: proxy.size.width)
                    }
                }
                .onPreferenceChange(EphemeralTextFieldContentWidthKey.self) { newValue in
                    contentWidth = newValue
                }
            
            if isInEditMode {
                editableContent($internalValue)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .frame(width: contentWidth, alignment: alignment)
                    .onChange(of: value) { newValue in
                        // Unfocus when changing the value externally.
                        isFocused = false
                        internalValue = newValue
                    }
                    .onSubmit { commit() }
                    .onExitCommand { cancel() }
                    .onReceive(unfocus) { action in
                        switch action {
                        case .commit:
                            commit()
                        case .cancel:
                            cancel()
                        }
                    }
                    .onChange(of: isFocused) { newValue in
                        if !newValue { isInEditMode = false }
                    }
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(TextAlignment(alignment))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(hoverBackground)
        .padding(.vertical, -4)
        .padding(.horizontal, -8)
        .offset(x: shakeOffset)
        .onChange(of: isInEditMode) { newValue in
            if newValue {
                internalValue = value
                isFocused = true
            }
        }
        .onChange(of: value) { newValue in
            internalValue = newValue
        }
        .onReceive(setFocus) { focus in
            guard focus != isInEditMode else { return }
            
            if focus {
                beginEditing()
            } else {
                cancel()
            }
        }
    }

    private func beginEditing() {
        guard isEnabled else { return }

        isInEditMode = true
    }
    
    private func commit() {
        guard validate(internalValue) else {
            self.internalValue = value
            shake()
            return
        }
        
        /// Update the external value with the edited value on submit,
        /// limiting to the allowed range.
        value = clamp(internalValue)
        internalValue = clamp(internalValue)

        isFocused = false
    }
    
    private func cancel() {
        /// Unfocus the field when pressing the escape key.
        isFocused = false
        
        /// Ugly hack alert!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            /// Restore initial value when cancelling out of the field.
            internalValue = value
        }
    }
    
    private func shake() {
        withAnimation(.easeInOut(duration: 0.04).repeatCount(7, autoreverses: true)) {
            shakeOffset = -7
        }
        /// Ugly hack alert (2)!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            shakeOffset = 0
        }
    }
    
    @State private var isHovered = false
    
    private var drawHoverBackground: Bool {
        isEnabled && (isHovered || isInEditMode)
    }
    
    @ViewBuilder
    private var hoverBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .foregroundColor(.white.opacity(0.07))
            .opacity(drawHoverBackground ? 1 : 0)
            .animation(.easeOut(duration: 0.24), value: isHovered)
    }
}

extension TextAlignment {
    init(_ alignment: Alignment) {
        switch alignment.horizontal {
        case .leading:
            self = .leading
        case .trailing:
            self = .trailing
        default:
            self = .center
        }
    }
}

#if DEBUG

struct EphemeralTextField_Previews: PreviewProvider {
    static var previews: some View {
        _Template()
    }

    struct _Template: View {
        @State var text = "Hello, World"

        var body: some View {
            VStack {
                EphemeralTextField($text) { value in
                    Text(value)
                } editableContent: { value in
                    TextField("", text: value)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

#endif
