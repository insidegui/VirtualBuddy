import SwiftUI
import VirtualCore
import BuddyKit

extension EnvironmentValues {
    @Entry var fullBleedBackgroundTransitionDuration: TimeInterval = BlurHashFullBleedBackground.defaultTransitionDuration
    @Entry var fullBleedBackgroundBrightness: Double = BlurHashFullBleedBackground.defaultBrightness
    @Entry var fullBleedBackgroundSaturation: Double = BlurHashFullBleedBackground.defaultSaturation

    var fullBleedBackgroundDimmed: Bool {
        get {
            fullBleedBackgroundBrightness < BlurHashFullBleedBackground.defaultBrightness
        }
        set {
            fullBleedBackgroundBrightness = newValue ? BlurHashFullBleedBackground.defaultBrightnessDimmed : BlurHashFullBleedBackground.defaultBrightness
            fullBleedBackgroundSaturation = newValue ? BlurHashFullBleedBackground.defaultSaturationDimmed : BlurHashFullBleedBackground.defaultSaturation
        }
    }
}

struct BlurHashFullBleedBackground: View {
    static let defaultTransitionDuration: TimeInterval = 1.0

    static let defaultBrightness: Double = -0.1
    static let defaultBrightnessDimmed: Double = -0.2

    static let defaultSaturation: Double = 1.3
    static let defaultSaturationDimmed: Double = 0.8

    var blurHash: BlurHashToken?

    init(_ blurHash: BlurHashToken?) {
        self.blurHash = blurHash
    }

    init(_ blurHashValue: String?) {
        self.init(blurHashValue.flatMap { BlurHashToken(value: $0) })
    }

    var body: some View {
        _BlurHashRepresentable(token: blurHash)
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct _BlurHashRepresentable: NSViewRepresentable {
    var token: BlurHashToken?

    typealias NSViewType = _BlurHashNSView

    func makeNSView(context: Context) -> _BlurHashNSView {
        _BlurHashNSView(frame: .zero)
    }

    func updateNSView(_ nsView: _BlurHashNSView, context: Context) {
        nsView.animationsDisabled = context.transaction.disablesAnimations
        nsView.transitionDuration = context.environment.fullBleedBackgroundTransitionDuration
        nsView.blurHash = token
        nsView.brightness = context.environment.fullBleedBackgroundBrightness
        nsView.saturation = context.environment.fullBleedBackgroundSaturation
    }

    final class _BlurHashNSView: NSView {
        private lazy var assetLayer: CALayer = .load(assetNamed: "FullBleedBlurHash", bundle: .virtualUI) ?? CALayer()

        var blurHash: BlurHashToken? {
            didSet {
                guard blurHash != oldValue else { return }
                image = blurHash.flatMap { NSImage.blurHash($0) }
            }
        }

        private var lastRenderedToken: BlurHashToken?

        @Invalidating(.layout)
        private var image: NSImage? = nil

        @Invalidating(.layout)
        var transitionDuration: TimeInterval = BlurHashFullBleedBackground.defaultTransitionDuration

        @Invalidating(.layout)
        var animationsDisabled: Bool = false

        var brightness: Double = BlurHashFullBleedBackground.defaultBrightness {
            didSet {
                guard brightness != oldValue else { return }
                withCurrentEnvironment {
                    assetLayer.setValue(brightness, forKeyPath: "filters.colorBrightness.inputAmount")
                }
            }
        }

        var saturation: Double = BlurHashFullBleedBackground.defaultSaturation {
            didSet {
                guard saturation != oldValue else { return }
                withCurrentEnvironment {
                    assetLayer.setValue(saturation, forKeyPath: "filters.colorSaturate.inputAmount")
                }
            }
        }

        override func layout() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            if assetLayer.superlayer == nil {
                platformLayer.addSublayer(assetLayer)
            }

            assetLayer.frame = bounds

            CATransaction.commit()

            guard blurHash != lastRenderedToken else { return }
            defer { lastRenderedToken = blurHash }

            withCurrentEnvironment {
                assetLayer.contents = image
            }
        }

        private func withCurrentEnvironment(perform block: () -> ()) {
            CATransaction.begin()
            CATransaction.setDisableActions(animationsDisabled)
            CATransaction.setAnimationDuration(animationsDisabled ? 0 : transitionDuration)

            block()

            CATransaction.commit()
        }
    }
}

#if DEBUG
extension BlurHashToken {
    static let previewSequoia = BlurHashToken(value: "eN86q8M1Hbyya7t-g$MpnTx,b;k9X8Vgr?osbHenWEeYoGj@aNaPah")
    static let previewSonoma = BlurHashToken(value: "ec8rzYaIWBj?a}iqosaxj?fkRFa2axayj[t%ofV[ayf6V]pGkBf5fi")
    static let previewVentura = BlurHashToken(value: "enHk%=ocoeW:Nb-8xEODaya#1fWWJAWExDEjR-jGazoJWCagw^s-Wp")
}

private struct BlurHashFullBleedBackgroundPreview: View {
    @State var token = BlurHashToken.virtualBuddyBackground

    @State private var brightness: Double = BlurHashFullBleedBackground.defaultBrightness
    @State private var effectiveBrightness: Double = BlurHashFullBleedBackground.defaultBrightness
    @State private var dimmed = false

    private let tokens: [BlurHashToken] = [
        .virtualBuddyBackground,
        .previewSequoia,
        .previewSonoma,
        .previewVentura
    ]

    var enableCycle = true

    var body: some View {
        BlurHashFullBleedBackground(token)
        /// Swap below environment modifiers to be able to test arbitrary brightness values in preview
//            .environment(\.fullBleedBackgroundBrightness, effectiveBrightness)
            .environment(\.fullBleedBackgroundDimmed, dimmed)
            .task(id: enableCycle) {
                guard enableCycle else { return }

                let delay = 3

                while true {
                    try! await Task.sleep(for: .seconds(delay))

                    let index = tokens.firstIndex(of: token)!

                    if index < tokens.count - 1 {
                        token = tokens[index + 1]
                    } else {
                        token = tokens[0]
                    }
                }
            }
            .frame(width: 1024, height: 1024)
            .overlay(alignment: .bottom) {
                Form {
                    Slider(value: $brightness, in: -1.0...1.0) {
                        HStack {
                            Text("Brightness")
                            Text(brightness, format: .percent.rounded(rule: .toNearestOrEven, increment: 1))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    Toggle("Dimmed", isOn: $dimmed)
                }
                .frame(width: 400)
                .padding()
                .background(Material.thin, in: RoundedRectangle(cornerRadius: 16))
                .chromeBorder(radius: 16)
                .padding()
            }
            .onChange(of: brightness) { newValue in
                withTransaction(\.disablesAnimations, true) {
                    effectiveBrightness = newValue
                }
            }
    }
}

#Preview {
    BlurHashFullBleedBackgroundPreview()
}
#endif // DEBUG
