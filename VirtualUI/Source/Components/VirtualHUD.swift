import SwiftUI
import BuddyUI
import VirtualCore

extension VirtualHUDNotification {
    static func mouse(disabled: Bool, systemImage: String) -> VirtualHUDNotification {
        VirtualHUDNotification(
            title: disabled ? "Mouse Disabled" : "Mouse Enabled",
            subtitle: disabled ? "Click anywhere to enable" : "Use toolbar to disable",
            glyph: systemImage,
            isDisabledState: disabled
        )
    }

    static func trackpad(disabled: Bool) -> VirtualHUDNotification {
        VirtualHUDNotification(
            title: disabled ? "Trackpad Disabled" : "Trackpad Enabled",
            subtitle: disabled ? "Click anywhere to enable" : "Use toolbar to disable",
            glyph: "rectangle.and.hand.point.up.left.filled",
            isDisabledState: disabled
        )
    }

    static func keyboard(disabled: Bool) -> VirtualHUDNotification {
        VirtualHUDNotification(
            title: disabled ? "Keyboard Disabled" : "Keyboard Enabled",
            subtitle: disabled ? "Click anywhere to enable" : "Use toolbar to disable",
            glyph: "keyboard",
            isDisabledState: disabled
        )
    }
}

struct VirtualHUDOverlay: View {

    var notification: VirtualHUDNotification

    var body: some View {
        _HUDRepresentable(notification: notification)
    }

    struct _HUDRepresentable: NSViewRepresentable {
        var notification: VirtualHUDNotification

        func makeNSView(context: Context) -> HUDView {
            HUDView()
        }

        func updateNSView(_ nsView: HUDView, context: Context) {
            nsView.notification = notification
        }

        final class HUDView: NSView, CALayerDelegate {
            var notification: VirtualHUDNotification = .keyboard(disabled: true) {
                didSet {
                    guard notification != oldValue else { return }
                    notificationView.rootView = VirtualHUDPill(notification: notification)
                    if assetLayer.speed.isZero {
                        assetLayer.ql_play()
                    } else {
                        assetLayer.ql_seek(to: 2.1)
                    }
                    needsLayout = true
                }
            }

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)

                setup()
            }

            required init?(coder: NSCoder) {
                fatalError()
            }

            private lazy var notificationView = NSHostingView(rootView: VirtualHUDPill(notification: notification))

            private lazy var assetContainer = NSView()
            private lazy var assetLayer = CALayer.load(assetNamed: "VirtualHUD", bundle: .virtualUI) ?? CALayer()
            private lazy var pillSizingLayer = assetLayer.sublayer(path: "clip.overlayContainer.pill") ?? CALayer()
            private lazy var contentPortalLayer = assetLayer.sublayer(path: "clip.overlayContainer.pill.pillContent.portal") ?? CALayer()

            func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
                NSNull()
            }

            private func setup() {
                wantsLayer = true

                addSubview(notificationView)
                addSubview(assetContainer)
                assetContainer.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    assetContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                    assetContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                    assetContainer.topAnchor.constraint(equalTo: topAnchor),
                    assetContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])

                assetContainer.platformLayer.addSublayer(assetLayer)
                assetContainer.platformLayer.delegate = self
                assetLayer.delegate = self

                platformLayer.setValue(false, forKeyPath: "allowsGroupBlending")

                assetLayer.beginTime = CACurrentMediaTime() + 0.5
                assetLayer.speed = 0
            }

            override func layout() {
                super.layout()

                assetLayer.position = CGPoint(
                    x: platformLayer.bounds.width * 0.5,
                    y: platformLayer.bounds.height
                )

                let size = notificationView.fittingSize
                notificationView.frame = CGRect(origin: .zero, size: size)
                pillSizingLayer.bounds = CGRect(x: 0, y: 0, width: size.width, height: pillSizingLayer.bounds.height)
                contentPortalLayer.bounds = CGRect(origin: .zero, size: size)
                contentPortalLayer.position = CGPoint(x: pillSizingLayer.bounds.width * 0.5, y: pillSizingLayer.bounds.height * 0.5)
                contentPortalLayer.setValue(notificationView.platformLayer, forKeyPath: "sourceLayer")
            }

            override var acceptsFirstResponder: Bool { false }

            override func isMousePoint(_ point: NSPoint, in rect: NSRect) -> Bool { false }

            override func hitTest(_ point: NSPoint) -> NSView? { nil }
        }
    }
}

struct VirtualHUDNotification: Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var subtitle: String
    var glyph: String
    var isDisabledState: Bool = false
}

extension VirtualHUDNotification {
    init(title: LocalizedStringResource, subtitle: LocalizedStringResource, glyph: String, isDisabledState: Bool = false) {
        self.init(
            id: UUID(),
            title: String(localized: title),
            subtitle: String(localized: subtitle),
            glyph: glyph,
            isDisabledState: isDisabledState
        )
    }
}

struct VirtualHUDPill: View {
    var notification: VirtualHUDNotification
    @State private var crossed: Bool

    init(notification: VirtualHUDNotification) {
        self.notification = notification
        /// Always start out with the opposite of the state the notification wants us to transition into
        /// so that the animation takes effect when we eventually set it to the final state.
        self.crossed = !notification.isDisabledState
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: notification.glyph)
                .font(.system(size: 22, weight: .medium))
                .crossOut(crossed)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)

                Text(notification.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .task(id: notification.isDisabledState) {
            do {
                try await Task.sleep(for: .milliseconds(900))
                crossed = notification.isDisabledState
            } catch { }
        }
    }
}

extension CALayer {
    func ql_pause() {
        let pausedTime = convertTime(CACurrentMediaTime(), from: nil)
        speed = 0
        timeOffset = pausedTime
    }

    func ql_seek(to time: TimeInterval) {
        if speed != .zero {
            ql_pause()
            DispatchQueue.main.async {
                self.ql_play()
            }
        }
        timeOffset = time
    }

    func ql_play() {
        let pausedTime = timeOffset
        speed = 1
        timeOffset = 0
        beginTime = 0
        let timeSincePause = convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        beginTime = timeSincePause
    }
}

extension View {
    func crossOut(_ crossed: Bool) -> some View {
        modifier(CrossOutModifier(crossed: crossed))
    }
}

struct CrossOutModifier: ViewModifier {
    var crossed = false
    var thickness: Double = 6

    static let animation = Animation.smooth(duration: 0.5, extraBounce: 0.2)

    func body(content: Content) -> some View {
        content
            .animation(Self.animation) { view in
                view.visualEffect { [crossed] view, _ in
                    view
                        .opacity(crossed ? 0.7 : 1.0)
                        .scaleEffect(crossed ? 0.9 : 1.0)
                }
            }
            .overlay {
                ZStack {
                    CrossOutShape(progress: crossed ? 1 : 0)
                        .stroke(style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round, miterLimit: 0))
                        .blendMode(.destinationOut)

                    CrossOutShape(progress: crossed ? 1 : 0)
                        .stroke(style: StrokeStyle(lineWidth: thickness * 0.5, lineCap: .round, lineJoin: .round, miterLimit: 0))
                }
                .animation(Self.animation, value: crossed)
                .opacity(crossed ? 1 : 0)
                .animation(.smooth(duration: 0.3).delay(crossed ? 0 : 0.1), value: crossed)
            }
    }
}

struct CrossOutShape: Shape {
    var progress: Double = 1

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX * progress, y: rect.minY + rect.maxY * (1 - progress)))

        return path
    }
}

@inline(__always)
@inlinable
func lerp(_ from: CGFloat, _ to: CGFloat, _ t: Double) -> CGFloat {
    let tt = CGFloat(t)
    return from + (to - from) * tt
}

#if DEBUG
struct _VirtualHUDPreview: View {
    @State private var notification = VirtualHUDNotification.keyboard(disabled: true)

    var body: some View {
        ZStack {
            Image(.previewScreen)
                .resizable()
                .frame(width: 1506, height: 1065)

            VirtualHUDOverlay(notification: notification)
        }
        .clipped()
        .padding(30)
        .task {
            do {
                try await Task.sleep(for: .milliseconds(1000))
                notification = .mouse(disabled: false, systemImage: "magicmouse")
                try await Task.sleep(for: .milliseconds(600))
                notification = .keyboard(disabled: true)
                try await Task.sleep(for: .milliseconds(600))
                notification = .trackpad(disabled: false)
            } catch { }
        }
//        .frame(width: 1000, height: 800, alignment: .top)
    }
}

#Preview {
    _VirtualHUDPreview()
}
#endif
