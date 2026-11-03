import AppKit

/// SkyLight's system-wide appearance API, also used by DarkModeBuddy. Resolve
/// the SPI at runtime so an OS without it can still use the other guest services.
@MainActor
enum SystemGuestAppearance {
    private final class API {
        let handle: UnsafeMutableRawPointer
        let get: @convention(c) () -> Int32
        let set: @convention(c) (Int32) -> Void

        init?() {
            guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else { return nil }
            guard let get = dlsym(handle, "SLSGetAppearanceThemeLegacy"),
                  let set = dlsym(handle, "SLSSetAppearanceThemeLegacy") else {
                dlclose(handle)
                return nil
            }
            self.handle = handle
            self.get = unsafeBitCast(get, to: (@convention(c) () -> Int32).self)
            self.set = unsafeBitCast(set, to: (@convention(c) (Int32) -> Void).self)
        }

        deinit { dlclose(handle) }
    }

    private static let api = API()

    static func isDarkModeEnabled() -> Bool? {
        guard let value = api?.get(), value == 0 || value == 1 else { return nil }
        return value == 1
    }

    static func setDarkModeEnabled(_ enabled: Bool) throws {
        guard let api else { throw GuestSessionError.remote("System appearance control is unavailable on this version of macOS.") }
        api.set(enabled ? 1 : 0)
    }

    static func observeChanges(_ receive: @escaping @MainActor () -> Void) -> () -> Void {
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { receive() }
        }
        return { center.removeObserver(observer) }
    }
}
