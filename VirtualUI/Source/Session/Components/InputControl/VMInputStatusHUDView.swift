import SwiftUI
import VirtualCore

/// Floats the input status HUD over the virtual machine's display.
struct VMInputStatusHUDOverlay: View {
    var presenter: VMInputStatusHUDPresenter
    var configuration: VBMacConfiguration

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.isLiquidGlassSupported)
    private var isLiquidGlassSupported

    var body: some View {
        AirGlassEffectContainer {
            ZStack {
                if let hud = presenter.hud {
                    VMInputStatusHUDView(hud: hud, configuration: configuration)
                        .airGlassEffectTransition(.materialize)
                        .modifier { view in
                            if #available(macOS 26, *) {
                                view
                            } else {
                                view.transition(.opacity.combined(with: .scale(scale: 0.86, anchor: .top)))
                            }
                        }
                }
            }
        }
        /// The HUD sits at the top so that it's close to the toolbar, where the input device toggles are.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(20)
        .animation(.default, value: presenter.hud == nil)
        /// The HUD is purely informative and must not get in the way of events meant for the guest.
        .allowsHitTesting(false)
    }
}

struct VMInputStatusHUDView: View {
    var hud: VMInputStatusHUD
    var configuration: VBMacConfiguration

    var body: some View {
        HStack(spacing: 12) {
            VMInputStatusBadge(symbolName: symbolName, isConnected: hud.isConnected, holdDuration: holdDuration)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .transition(.blurReplace)

                HStack(spacing: 5) {
                    Text(coachingPrefix)
                        .transition(.blurReplace)

                    HStack(spacing: 2) {
                        ForEach(hud.device.toggleShortcutSymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 18, height: 18)
                                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                    .foregroundStyle(.primary)
                    /// Prevent each item from animating independently.
                    .geometryGroup()

                    if let coachingSuffix {
                        Text(coachingSuffix)
                            .transition(.blurReplace)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.leading, 10)
        .padding(.trailing, 24)
        .padding(.vertical, 10)
        .airMaterialBackground(
            visualEffect: .hudWindow,
            /// The slight tint keeps the text legible regardless of what the guest is displaying behind the HUD.
            glassEffect: .clear.tint(.black.opacity(0.3)),
            in: Capsule(style: .continuous)
        )
        .environment(\.colorScheme, .dark)
        .animation(.default, value: hud)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .onChange(of: hud, initial: true) {
            guard hud.phase == .changed else { return }
            AccessibilityNotification.Announcement(title).post()
        }
    }

    private var holdDuration: TimeInterval? {
        guard case .holding(let remaining) = hud.phase else { return nil }
        return remaining
    }

    private var deviceName: String {
        switch hud.device {
        case .keyboard: "Keyboard"
        case .pointingDevice: configuration.pointingDeviceName.capitalized
        }
    }

    private var symbolName: String {
        switch hud.device {
        case .keyboard: configuration.keyboardDeviceSFSymbol
        case .pointingDevice: configuration.pointingDeviceSFSymbol
        }
    }

    private var title: String {
        switch hud.phase {
        case .holding:
            hud.isConnected ? "Disconnecting \(deviceName)…" : "Connecting \(deviceName)…"
        case .changed:
            hud.isConnected ? "\(deviceName) Connected" : "\(deviceName) Disconnected"
        }
    }

    private var coachingPrefix: String {
        switch hud.phase {
        case .holding: "Keep holding"
        case .changed: "Hold"
        }
    }

    private var coachingSuffix: String? {
        switch hud.phase {
        case .holding: nil
        case .changed: hud.isConnected ? "to disconnect" : "to reconnect"
        }
    }

    private var accessibilityDescription: String {
        let shortcut = hud.device.toggleShortcutSymbols.joined()

        return [title, [coachingPrefix, shortcut, coachingSuffix].compactMap(\.self).joined(separator: " ")]
            .joined(separator: ", ")
    }
}

/// The input device's icon, struck through when it's disconnected and
/// surrounded by a ring that fills up while the toggle shortcut is being held down.
private struct VMInputStatusBadge: View {
    var symbolName: String
    var isConnected: Bool
    /// The time it takes for the toggle shortcut that's being held down to take effect, `nil` when it's not being held down.
    var holdDuration: TimeInterval?

    private var slash: some Shape {
        VMInputStatusSlash()
            .trim(from: 0, to: isConnected ? 0 : 1)
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 16, weight: .medium))
            .frame(width: 24, height: 24)
            .mask {
                /// Leaves a gap between the icon and the slash going through it.
                Rectangle()
                    .overlay {
                        slash
                            .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .overlay {
                slash
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .opacity(isConnected ? 1 : 0.6)
            .frame(width: 40, height: 40)
            .background(.white.opacity(isConnected ? 0.22 : 0.1), in: Circle())
            .overlay {
                if let holdDuration {
                    VMInputHoldProgressRing(duration: holdDuration)
                        .transition(.opacity)
                }
            }
    }
}

private struct VMInputStatusSlash: Shape {
    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: 3, dy: 3)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct VMInputHoldProgressRing: View {
    var duration: TimeInterval

    @State private var progress = 0.0

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(1)
            .onAppear {
                withAnimation(.linear(duration: duration)) {
                    progress = 1
                }
            }
    }
}

#if DEBUG
#Preview("Input Status HUD") {
    @Previewable @State var presenter = VMInputStatusHUDPresenter()
    @Previewable @State var connectedDevices = Set(VMInputDevice.allCases)

    VStack(spacing: 12) {
        ForEach(VMInputDevice.allCases, id: \.self) { device in
            HStack {
                Button("Hold \(device.toggleShortcutSymbols.joined())") {
                    let remaining = VMInputToggleHoldRecognizer.holdDuration - VMInputToggleHoldRecognizer.coachingDelay

                    presenter.holdBegan(for: device, isConnected: connectedDevices.contains(device), remaining: remaining)

                    Task {
                        try? await Task.sleep(for: .seconds(remaining))

                        connectedDevices.formSymmetricDifference([device])
                        presenter.statusChanged(for: device, isConnected: connectedDevices.contains(device))
                    }
                }

                Button("Toggle") {
                    connectedDevices.formSymmetricDifference([device])
                    presenter.statusChanged(for: device, isConnected: connectedDevices.contains(device))
                }
            }
        }

        Button("Cancel Hold") {
            presenter.holdCancelled()
        }
    }
    .frame(width: 600, height: 400)
    .overlay {
        VMInputStatusHUDOverlay(presenter: presenter, configuration: .preview)
    }
    .previewWallpaper()
}

#Preview("Input Status HUD States") {
    VStack(spacing: 20) {
        VMInputStatusHUDView(hud: .init(device: .keyboard, isConnected: true, phase: .holding(remaining: 1.6)), configuration: .preview)
        VMInputStatusHUDView(hud: .init(device: .keyboard, isConnected: false, phase: .changed), configuration: .preview)
        VMInputStatusHUDView(hud: .init(device: .pointingDevice, isConnected: false, phase: .holding(remaining: 1.6)), configuration: .preview)
        VMInputStatusHUDView(hud: .init(device: .pointingDevice, isConnected: true, phase: .changed), configuration: .preview)
    }
    .padding(60)
    .previewWallpaper()
}
#endif
