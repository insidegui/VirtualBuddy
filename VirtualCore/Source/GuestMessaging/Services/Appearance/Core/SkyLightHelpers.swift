import Foundation
import OSLog

extension VMSystemAppearance {
    static var current: Self {
        get {
            guard VBCheckSkyLightSPI() else {
                assertionFailure("SkyLight SPI is not available on this system")
                return .light
            }
            return VMSystemAppearance(rawValue: SLSGetAppearanceThemeLegacy()) ?? .light
        }
        set {
            guard VBCheckSkyLightSPI() else {
                assertionFailure("SkyLight SPI is not available on this system")
                return
            }

            SLSSetAppearanceThemeLegacy(newValue.rawValue)
        }
    }

    private static let center = DistributedNotificationCenter.default()

    static func addObserver(_ closure: @escaping (VMSystemAppearance) -> Void) -> any NSObjectProtocol {
        center.addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { note in
            closure(.current)
        }
    }

    static func removeObserver(_ observer: Any?) {
        guard let observer else { return }
        center.removeObserver(observer)
    }
}
