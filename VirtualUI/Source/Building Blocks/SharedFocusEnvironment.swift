import SwiftUI
import VirtualCore

extension EnvironmentValues {
    var unfocusActiveField: VoidSubject {
        get { self[UnfocusActiveFieldEnvironmentKey.self] }
        set { self[UnfocusActiveFieldEnvironmentKey.self] = newValue }
    }
}

private struct UnfocusActiveFieldEnvironmentKey: EnvironmentKey {
    static var defaultValue = VoidSubject()
}
