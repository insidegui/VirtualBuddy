import SwiftUI
import Combine

enum UnfocusFieldAction {
    case commit
    case cancel
}

typealias UnfocusFieldSubject = PassthroughSubject<UnfocusFieldAction, Never>

extension EnvironmentValues {
    var unfocusActiveField: UnfocusFieldSubject {
        get { self[UnfocusActiveFieldEnvironmentKey.self] }
        set { self[UnfocusActiveFieldEnvironmentKey.self] = newValue }
    }
}

extension View {
    func unfocusOnTap() -> some View {
        modifier(UnfocusOnTap())
    }
}

private struct UnfocusOnTap: ViewModifier {
    
    @Environment(\.unfocusActiveField)
    private var unfocus
    
    func body(content: Content) -> some View {
        content
            .onTapGesture { unfocus.send(.commit) }
    }
    
}

private struct UnfocusActiveFieldEnvironmentKey: EnvironmentKey {
    static var defaultValue = UnfocusFieldSubject()
}
