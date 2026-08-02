import SwiftUI
import SwiftUIIntrospect

/// A `Form` with the `.grouped` style that automatically resizes itself so that it
/// perfectly fits its contents in the vertical axis.
struct SelfSizingGroupedForm<Content: View>: View {
    var minHeight: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var contentHeight: CGFloat = 0

    private let disabled = UserDefaults.standard.bool(forKey: "VBDisableSelfSizingGroupedForm")

    var body: some View {
        ZStack {
            form
        }
        .frame(height: max(minHeight, contentHeight))
    }

    @ViewBuilder
    private var form: some View {
        let form = Form {
            content()
        }
        .formStyle(.grouped)

        if #available(macOS 15.0, *) {
            form.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height
            } action: { _, newHeight in
                guard !disabled else { return }
                guard newHeight != contentHeight else { return }
                guard newHeight > 0, newHeight.isFinite else { return }
                contentHeight = newHeight
            }
        } else {
            /// The grouped `Form` is no longer backed by an introspectable `NSScrollView`
            /// on modern macOS, so introspection is only used where the native
            /// scroll geometry API is unavailable.
            form.introspect(.scrollView, on: .macOS(.v13, .v14)) { scrollView in
                guard !disabled else { return }
                guard let frame = scrollView.documentView?.frame else { return }
                guard frame.height != contentHeight else { return }
                guard frame.height > 0, frame.height.isFinite, !frame.height.isNaN else { return }
                /// Ugly, I know, but I reaaaaally wanted the form to look a specific way 🥺
                DispatchQueue.main.async {
                    contentHeight = frame.height
                }
            }
        }
    }
}

#if DEBUG

private struct _Preview: View {
    @State var someText = "Hello, World"
    @State var someBool = true

    var body: some View {
        SelfSizingGroupedForm(minHeight: 100) {
            TextField("This is a text field", text: $someText)
            Toggle("This is a toggle", isOn: $someBool)
        }
    }
}

#Preview("SelfSizingGroupedForm") {
    _Preview()
}
#endif
