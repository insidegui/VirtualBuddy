import Foundation

public final class VBMemoryLeakDebugAssertions {
    @inlinable
    public static func vb_objectShouldBeReleasedSoon(_ object: AnyObject, after interval: TimeInterval = 0.5) {
        #if DEBUG
        _vb_objectShouldBeReleasedSoon(object, after: interval)
        #endif
    }

    @inlinable
    public static func vb_objectIsBeingReleased(_ object: AnyObject) {
        #if DEBUG
        _vb_objectIsBeingReleased(object)
        #endif
    }

    #if DEBUG
    public static let _disableFlag = "VBDisableMemoryLeakAssertions"

    public static var _vb_debugAssertionsEnabled: Bool { !UserDefaults.standard.bool(forKey: _disableFlag) }

    public static var _releasedObjects = Set<String>()

    @inlinable
    public static func _objectID(_ object: AnyObject) -> String {
        String(describing: Unmanaged.passUnretained(object).toOpaque())
    }

    @inlinable
    public static func _vb_objectShouldBeReleasedSoon(_ object: AnyObject, after interval: TimeInterval) {
        guard _vb_debugAssertionsEnabled else { return }

        let id = _objectID(object)
        let className = String(describing: type(of: object))

        let description: String

        if let window = object as? NSWindow {
            let title = window.title
            description = "#\(id) (\(className) - \"\(title)\")"
        } else {
            description = "#\(id) (\(className) - \"\(String(describing: object))\")"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            assert(_releasedObjects.contains(id), "💦 POSSIBLE LEAK: \(description) was not released when expected (set \(_disableFlag) defaults flag to disable this)")
        }
    }

    @inlinable
    public static func _vb_objectIsBeingReleased(_ object: AnyObject) {
        guard _vb_debugAssertionsEnabled else { return }

        _releasedObjects.insert(_objectID(object))
    }
    #endif
}
