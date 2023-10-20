import Foundation

/// Wraps a reference type as a weak reference.
/// Useful as value type in collections when holding a strong reference to the objects is undesirable.
public struct WeakReference<Object: AnyObject> {
    public private(set) weak var object: Object?

    public init(_ object: Object) {
        self.object = object
    }
}

extension WeakReference: Equatable where Object: Equatable { }
extension WeakReference: Hashable where Object: Hashable { }
