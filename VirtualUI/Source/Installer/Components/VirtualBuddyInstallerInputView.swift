import SwiftUI

struct VirtualBuddyInstallerInputView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @FocusState private var isFocused: Bool

    var body: some View {
        content()
            .focused($isFocused)
            .task { isFocused = true }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .padding()
            .controlGroup()
            .frame(maxWidth: 500)
    }
}
