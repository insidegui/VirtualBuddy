import SwiftUI

extension View {
    @ViewBuilder
    func keyboardNavigation(autofocus: Bool = true, onMove: @escaping (_ direction: MoveCommandDirection) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            modifier(KeyboardNavigationModifier_Modern(autofocus: autofocus, onMove: onMove))
        } else {
            modifier(KeyboardNavigationModifier_Legacy(autofocus: autofocus, onMove: onMove))
        }
    }
}

@available(macOS 14.0, *)
private struct KeyboardNavigationModifier_Modern: ViewModifier {
    var autofocus: Bool
    var onMove: (MoveCommandDirection) -> Void

    @FocusState private var isFocused

    func body(content: Content) -> some View {
        content
            .focusable(true)
            .focused($isFocused)
            .onMoveCommand { direction in
                onMove(direction)
            }
            .focusEffectDisabled()
            .task {
                guard autofocus else { return }
                isFocused = true
            }
    }

}

private struct KeyboardNavigationModifier_Legacy: ViewModifier {
    var autofocus: Bool
    var onMove: (MoveCommandDirection) -> Void

    @FocusState private var isFocused

    func body(content: Content) -> some View {
        content
            .overlay {
                /// Horrible hack to hide the focus ring while still allowing for keyboard navigation.
                Rectangle()
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .focusable(true)
                    .focused($isFocused)
                    .onMoveCommand { direction in
                        onMove(direction)
                    }
            }
            .task {
                guard autofocus else { return }
                isFocused = true
            }
    }
}

extension View {
    @ViewBuilder
    func backported_focusEffectDisabled(_ disabled: Bool = true) -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled(disabled)
        } else {
            self
        }
    }
}
