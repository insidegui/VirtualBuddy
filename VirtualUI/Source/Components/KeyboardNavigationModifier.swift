import SwiftUI

extension View {
    func keyboardNavigation(_ onMove: @escaping (_ direction: MoveCommandDirection) -> Void) -> some View {
        modifier(KeyboardNavigationModifier(onMove: onMove))
    }
}

private struct KeyboardNavigationModifier: ViewModifier {
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
            .task { isFocused = true }
    }
}
