//
//  EphemeralTextField.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI

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
    
    init(_ value: Binding<Value>,
         @ViewBuilder staticContent: @escaping (Value) -> StaticContent,
         @ViewBuilder editableContent: @escaping (Binding<Value>) -> EditableContent,
         clamp: @escaping (Value) -> Value = { $0 },
         validate: @escaping (Value) -> Bool = { _ in  true })
    {
        self._value = value
        self._internalValue = .init(wrappedValue: value.wrappedValue)
        self.staticContent = staticContent
        self.editableContent = editableContent
        self.clamp = clamp
        self.validate = validate
    }
    
    @State private var internalValue: Value
    
    @Environment(\.unfocusActiveField)
    private var unfocus
    
    @FocusState
    private var isFocused: Bool

    @State private var isInEditMode = false
    
    @State private var contentWidth: CGFloat = 40

    var body: some View {
        ZStack {
            staticContent(internalValue)
                .contentShape(Rectangle())
                .onTapGesture { isInEditMode = true }
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
                    .frame(width: contentWidth, alignment: .trailing)
                    .onChange(of: value) { newValue in
                        // Unfocus when changing the value externally.
                        isFocused = false
                        internalValue = newValue
                    }
                    .onSubmit {
                        guard validate(internalValue) else { return }
                        
                        /// Update the external value with the edited value on submit,
                        /// limiting to the allowed range.
                        value = clamp(internalValue)
                        internalValue = clamp(internalValue)

                        isFocused = false
                    }
                    .onExitCommand {
                        /// Unfocus the field when pressing the escape key.
                        isFocused = false
                        
                        /// Ugly hack alert!
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            /// Restore initial value when cancelling out of the field.
                            internalValue = value
                        }
                    }
                    .onReceive(unfocus) {
                        isFocused = false
                    }
                    .onChange(of: isFocused) { newValue in
                        if !newValue { isInEditMode = false }
                    }
            }
        }
        .monospacedDigit()
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(hoverBackground)
        .padding(.vertical, -4)
        .padding(.horizontal, -8)
        .onChange(of: isInEditMode) { newValue in
            if newValue {
                internalValue = value
                isFocused = true
            }
        }
        .onChange(of: value) { newValue in
            internalValue = newValue
        }
    }
    
    @State private var isHovered = false
    
    @ViewBuilder
    private var hoverBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .foregroundColor(.white.opacity(0.07))
            .opacity(isHovered || isInEditMode ? 1 : 0)
            .animation(.easeOut(duration: 0.24), value: isHovered)
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
