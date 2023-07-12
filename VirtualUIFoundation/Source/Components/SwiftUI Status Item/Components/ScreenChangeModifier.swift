import SwiftUI
import Combine

typealias ViewScreenChangeBlock = (NSScreen?) -> Void

extension View {
    /// Calls the specified block whenever the window that's hosting the view moves between displays.
    func onScreenChanged(perform block: @escaping ViewScreenChangeBlock) -> some View {
        modifier(ScreenChangeModifier(onScreenChanged: block))
    }

    /// Injects the `screen` environment value, updating it whenever the window that's hosting
    /// the view moves between displays.
    func trackScreen() -> some View {
        modifier(ScreenEnvironmentInjectionModifier())
    }
}

private struct ScreenEnvironmentKey: EnvironmentKey {
    static var defaultValue: NSScreen? = .main
}

extension EnvironmentValues {
    fileprivate(set) var screen: NSScreen? {
        get { self[ScreenEnvironmentKey.self] }
        set { self[ScreenEnvironmentKey.self] = newValue }
    }
}

private struct ScreenChangeModifier: ViewModifier {

    var onScreenChanged: ViewScreenChangeBlock

    func body(content: Content) -> some View {
        content
            .background(ScreenTrackingHostView(onScreenChanged: onScreenChanged))
    }

}

private struct ScreenEnvironmentInjectionModifier: ViewModifier {

    @State private var screen: NSScreen? = .main

    func body(content: Content) -> some View {
        content
            .environment(\.screen, screen)
            .onScreenChanged { screen = $0 }
    }

}

private struct ScreenTrackingHostView: NSViewRepresentable {

    var onScreenChanged: ViewScreenChangeBlock

    typealias NSViewType = _ScreenTrackingView

    func makeNSView(context: Context) -> _ScreenTrackingView {
        _ScreenTrackingView(onScreenChanged: onScreenChanged)
    }

    func updateNSView(_ nsView: _ScreenTrackingView, context: Context) {

    }

}

private final class _ScreenTrackingView: NSView {

    var onScreenChanged: ViewScreenChangeBlock
    private var previousScreenDisplayID: Int?

    init(onScreenChanged: @escaping ViewScreenChangeBlock) {
        self.onScreenChanged = onScreenChanged

        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isOpaque: Bool { false }

    private var screenCancellable: AnyCancellable?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        screenCancellable?.cancel()

        guard let window else { return }

        screenCancellable = window
            .publisher(for: \.screen, options: [.initial, .new])
            .sink { [weak self] screen in
                guard let self = self else { return }

                let currentScreenDisplayID = screen?.displayID?.intValue

                guard currentScreenDisplayID != self.previousScreenDisplayID else { return }

                self.onScreenChanged(screen)

                self.previousScreenDisplayID = currentScreenDisplayID
            }
    }

}

extension NSScreen {
    var displayID: NSNumber? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }

    var hasTallMenuBar: Bool { safeAreaInsets.top > 0 }
}
