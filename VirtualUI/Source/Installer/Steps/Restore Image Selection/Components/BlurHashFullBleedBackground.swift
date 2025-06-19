import SwiftUI
import VirtualCore
import BuddyKit

private extension EnvironmentValues {
    @Entry var fullBleedBackgroundTransitionDuration: TimeInterval = BlurHashFullBleedBackground.defaultTransitionDuration
    @Entry var fullBleedBackgroundBrightness: Double = BlurHashFullBleedBackground.defaultBrightness
    @Entry var fullBleedBackgroundSaturation: Double = BlurHashFullBleedBackground.defaultSaturation
    @Entry var fullBleedBackgroundBlurRadius: Double = BlurHashFullBleedBackground.defaultBlurRadius

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

public extension View {
    func fullBleedBackgroundDimmed(_ dimmed: Bool = true) -> some View {
        environment(\.fullBleedBackgroundDimmed, dimmed)
    }
    func fullBleedBackgroundBrightness(_ brightness: Double?) -> some View {
        environment(\.fullBleedBackgroundBrightness, brightness ?? BlurHashFullBleedBackground.defaultBrightness)
    }
    func fullBleedBackgroundSaturation(_ saturation: Double?) -> some View {
        environment(\.fullBleedBackgroundSaturation, saturation ?? BlurHashFullBleedBackground.defaultSaturation)
    }
    func fullBleedBackgroundBlurRadius(_ radius: Double?) -> some View {
        environment(\.fullBleedBackgroundBlurRadius, radius ?? BlurHashFullBleedBackground.defaultBlurRadius)
    }
}

struct BlurHashFullBleedBackground: View {
    static let defaultTransitionDuration: TimeInterval = 1.0

    static let defaultBrightness: Double = -0.1
    static let defaultBrightnessDimmed: Double = -0.2

    static let defaultSaturation: Double = 1.3
    static let defaultSaturationDimmed: Double = 0.8

    static let defaultBlurRadius: Double = 22

    enum Content: Hashable {
        case blurHash(BlurHashToken)
        case customImage(NSImage)
    }

    var content: Content?

    init(content: Content?) {
        self.content = content
    }

    init(blurHash: BlurHashToken?) {
        self.content = blurHash.flatMap { .blurHash($0) }
    }

    init(image: NSImage?) {
        self.content = image.flatMap { .customImage($0) }
    }

    init(_ blurHashValue: String?) {
        self.init(blurHash: blurHashValue.flatMap { BlurHashToken(value: $0) })
    }

    var body: some View {
        _BlurHashRepresentable(content: content)
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct _BlurHashRepresentable: NSViewRepresentable {
    typealias Content = BlurHashFullBleedBackground.Content

    var content: Content?

    typealias NSViewType = _BlurHashNSView

    func makeNSView(context: Context) -> _BlurHashNSView {
        _BlurHashNSView(frame: .zero)
    }

    func updateNSView(_ nsView: _BlurHashNSView, context: Context) {
        nsView.animationsDisabled = context.transaction.disablesAnimations
        nsView.transitionDuration = context.environment.fullBleedBackgroundTransitionDuration

        switch content {
        case .blurHash(let token):
            nsView.blurHash = token
        case .customImage(let image):
            nsView.customImage = image
        case .none:
            nsView.blurHash = nil
            nsView.customImage = nil
        }

        nsView.brightness = context.environment.fullBleedBackgroundBrightness
        nsView.saturation = context.environment.fullBleedBackgroundSaturation
        nsView.blurRadius = context.environment.fullBleedBackgroundBlurRadius
    }

    final class _BlurHashNSView: NSView {
        private lazy var assetLayer: CALayer = .load(assetNamed: "FullBleedBlurHash", bundle: .virtualUI) ?? CALayer()

        var blurHash: BlurHashToken? {
            didSet {
                guard blurHash != oldValue else { return }
                image = blurHash.flatMap { NSImage.blurHash($0) }
            }
        }

        var customImage: NSImage? {
            didSet {
                guard customImage != oldValue else { return }
                guard let customImage else {
                    image = nil
                    return
                }

                let scale = 0.01
                let size = CGSize(width: customImage.size.width * scale, height: customImage.size.height * scale)
                UILog("Custom image size: \(size)")

                image = NSImage(size: size, flipped: true) { rect in
                    customImage.draw(in: rect)
                    return true
                }
            }
        }

        private var lastRenderedToken: BlurHashToken?
        private var lastRenderedImage: NSImage?

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

        var blurRadius: Double = BlurHashFullBleedBackground.defaultBlurRadius {
            didSet {
                guard blurRadius != oldValue else { return }
                withCurrentEnvironment {
                    assetLayer.setValue(blurRadius, forKeyPath: "filters.gaussianBlur.inputRadius")
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

            guard blurHash != lastRenderedToken || image != lastRenderedImage else { return }
            defer {
                lastRenderedToken = blurHash
                lastRenderedImage = image
            }

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
        BlurHashFullBleedBackground(blurHash: token)
        /// Swap below environment modifiers to be able to test arbitrary brightness values in preview
//            .environment(\.fullBleedBackgroundBrightness, effectiveBrightness)
            .environment(\.fullBleedBackgroundDimmed, dimmed)
            .task(id: enableCycle) {
                guard enableCycle else { return }

                let delay = 3

                while true {
                    do {
                        try await Task.sleep(for: .seconds(delay))

                        let index = tokens.firstIndex(of: token)!

                        if index < tokens.count - 1 {
                            token = tokens[index + 1]
                        } else {
                            token = tokens[0]
                        }
                    } catch {
                        break
                    }
                }
            }
            .frame(width: 512, height: 512)
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

#Preview("Blur Hash") {
    BlurHashFullBleedBackgroundPreview()
}

#Preview("Custom Image") {
    BlurHashFullBleedBackground(image: .blurHashPreview)
}

private extension NSImage {
    static let blurHashPreview = NSImage(contentsOfFile: "/System/Library/Desktop Pictures/Sonoma.heic")!
}
#endif // DEBUG
