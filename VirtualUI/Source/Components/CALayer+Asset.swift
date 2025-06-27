import Cocoa
import OSLog

public extension CALayer {
    static let log = Logger(subsystem: VirtualUIConstants.subsystemName, category: "CALayer+Asset")
}

public extension CALayer {

    /// Loads a `CALayer` from a Core Animation Archive asset.
    ///
    /// - Parameters:
    ///   - assetName: The name of the asset in the asset catalog.
    ///   - bundle: The bundle where the asset catalog is located.
    /// - Returns: The `CALayer` loaded from the asset in the asset catalog, `nil` in case of failure.
    static func load(assetNamed assetName: String, bundle: Bundle = .main) -> CALayer? {
        guard let asset = NSDataAsset(name: assetName, bundle: bundle) else {
            assertionFailure("Asset not found")
            log.fault("Missing asset \(assetName, privacy: .public)")
            return nil
        }

        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: asset.data)
            unarchiver.requiresSecureCoding = false

            let rootObject = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)

            guard let dictionary = rootObject as? NSDictionary else {
                assertionFailure("Failed to load asset")
                log.fault("Failed to load asset \(assetName, privacy: .public)")
                return nil
            }

            guard let layer = dictionary["rootLayer"] as? CALayer else {
                assertionFailure("Root layer not found")
                log.fault("Failed to load root layer from asset \(assetName, privacy: .public)")
                return nil
            }

            return layer
        } catch {
            assertionFailure(String(describing: error))
            log.fault("Unarchive failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func sublayer<T: CALayer>(named name: String, of type: T.Type = CALayer.self) -> T? {
        return sublayers?.first(where: { $0.name == name }) as? T
    }

    func sublayer<T: CALayer>(path: String, of type: T.Type = CALayer.self) -> T? {
        let components = path.components(separatedBy: ".")
        var target: CALayer? = self
        for component in components {
            target = target?.sublayer(named: component, of: CALayer.self)
        }
        return target as? T
    }
}

extension CALayer {
    static func resize(_ targetLayer: CALayer?,
                       within containerBounds: CGRect,
                       multiplier: CGFloat = 1,
                       offset: CGPoint = .zero,
                       gravity: CALayerContentsGravity = .resizeAspect,
                       resetPosition: Bool = false,
                       disableAnimations: Bool = false)
    {
        assert([.resizeAspect, .resizeAspectFill, .resize, .center].contains(gravity), "Unsupported layer gravity")

        if disableAnimations {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
        }
        defer { if disableAnimations { CATransaction.commit() } }

        let fn: (CGFloat, CGFloat) -> CGFloat = gravity == .resizeAspectFill ? max : min

        guard let targetLayer = targetLayer else { return }

        let layerWidth = targetLayer.bounds.width
        let layerHeight = targetLayer.bounds.height

        let aspectWidth  = containerBounds.width / layerWidth
        let aspectHeight = containerBounds.height / layerHeight

        let ratioWidth: CGFloat
        let ratioHeight: CGFloat

        switch gravity {
        case .resize:
            ratioWidth = aspectWidth * multiplier
            ratioHeight = aspectHeight * multiplier
        case .center:
            ratioWidth = multiplier
            ratioHeight = multiplier
        default:
            ratioWidth = fn(aspectWidth, aspectHeight) * multiplier
            ratioHeight = fn(aspectWidth, aspectHeight) * multiplier
        }

        let scale = CATransform3DMakeScale(ratioWidth,
                                           ratioHeight,
                                           1)
        let translation = CATransform3DMakeTranslation((containerBounds.width - (layerWidth * ratioWidth)) / 2.0 - offset.x,
                                                       (containerBounds.height - (layerHeight * ratioHeight)) / 2.0 - offset.y,
                                                       0)

        if resetPosition {
            targetLayer.anchorPoint = .zero
            targetLayer.position = .zero
        }

        targetLayer.transform = CATransform3DConcat(scale, translation)
    }
}
