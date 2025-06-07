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

    func sublayer<T: CALayer>(named name: String, of type: T.Type) -> T? {
        return sublayers?.first(where: { $0.name == name }) as? T
    }

    func sublayer<T: CALayer>(path: String, of type: T.Type) -> T? {
        let components = path.components(separatedBy: ".")
        var target: CALayer? = self
        for component in components {
            target = target?.sublayer(named: component, of: CALayer.self)
        }
        return target as? T
    }
}

public extension CALayer {

    func resizeLayer(_ targetLayer: CALayer?) {
        guard let targetLayer = targetLayer else { return }

        let layerWidth = targetLayer.bounds.width
        let layerHeight = targetLayer.bounds.height

        let aspectWidth  = bounds.width / layerWidth
        let aspectHeight = bounds.height / layerHeight

        let ratio = min(aspectWidth, aspectHeight)

        let scale = CATransform3DMakeScale(ratio,
                                           ratio,
                                           1)
        let translation = CATransform3DMakeTranslation((bounds.width - (layerWidth * ratio))/2.0,
                                                       (bounds.height - (layerHeight * ratio))/2.0,
                                                       0)

        targetLayer.transform = CATransform3DConcat(scale, translation)
    }

}
