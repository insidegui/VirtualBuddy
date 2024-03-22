import SwiftUI
import Combine

public extension EnvironmentValues {
    
    /// Call to open a SwiftUI view hierarchy in a new macOS window.
    /// The SwiftUI view defines the size and resizability of the window, use SwiftUI's `frame`
    /// modifier to customize the behavior.
    ///
    /// See ``OpenCocoaWindowAction`` for more information.
    fileprivate(set) var openCocoaWindow: OpenCocoaWindowAction {
        get { self[OpenCocoaWindowActionKey.self] }
        set { self[OpenCocoaWindowActionKey.self] = newValue }
    }
    
}

fileprivate struct OpenCocoaWindowActionKey: EnvironmentKey {
    static let defaultValue = OpenCocoaWindowAction.default
}

/// An action that opens a new Mac window with SwiftUI content.
///
/// Read the `openCocoaWindow` environment value to get an instance of this structure for a given Environment.
/// Call the instance to open a new window with the SwiftUI content provided. You call the instance directly because it defines a ``callAsFunction(_:)``
/// method that Swift calls when you call the instance.
///
/// ## Example:
///
/// ```swift
/// struct TestNewWindowView: View {
///
///     @Environment(\.openCocoaWindow) private var openWindow
///
///     var body: some View {
///         Button {
///             openWindow {
///                 Text("I'm in a new window")
///                     .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
///             }
///         } label: {
///             Text("Open New Window")
///         }
///     }
///
/// }
/// ```
public struct OpenCocoaWindowAction {

    public static let `default` = OpenCocoaWindowAction()

    /// A token represents a window that's been opened by ``OpenCocoaWindowAction``.
    ///
    /// You may use the token to close the window from outside the view hierarchy hosted within it, such
    /// as from the SwiftUI view hierarchy that created the window in the first place.
    ///
    /// ``Token`` is an `ObservableObject`, so your view may observe it in order to be notified of
    /// when the window has been closed via the ``isOpen`` published property.
    public final class Token: Hashable, ObservableObject {
        
        private var id: String

        init(id: String) {
            self.id = id
        }
        
        fileprivate lazy var cancellables = Set<AnyCancellable>()
        
        fileprivate func invalidate() {
            cancellables.removeAll()
        }
        
        /// `true` when the window represented by this token has been opened and hasn't yet been closed
        /// by either the user or your code.
        @Published public internal(set) var isOpen = false
        
        /// Closes the window that was opened using ``OpenCocoaWindowAction``.
        @MainActor
        public func close() {
            OpenCocoaWindowManager.shared[self]?.close()
        }
    }
    
    @MainActor
    private var manager: OpenCocoaWindowManager { .shared }
    
    /// Opens a new Mac window with the SwiftUI content provided.
    /// - Parameter content: A view builder that provides the contents of the window.
    /// - Returns: A ``Token`` that can be used to monitor or modify the state of the new window.
    ///
    /// Don’t call this method directly. Swift calls it when you call the ``OpenCocoaWindowAction``
    /// structure that you get from the Environment.
    @MainActor
    @discardableResult
    public func callAsFunction<Content>(id: String? = nil, @ViewBuilder _ content: @escaping () -> Content) -> Token where Content: View {
        let token = Token(id: id ?? UUID().uuidString)

        if let existingController = manager[token] {
            existingController.showWindow(nil)
        } else {
            let controller = HostingWindowController(id: id, rootView: content())

            manager[token] = controller
        }
        
        return token
    }
    
    /// Closes a window previously opened through ``OpenCocoaWindowAction``.
    /// - Parameter token: The token returned from calling ``OpenCocoaWindowAction``  as a function.
    ///
    /// You may also just call ``Token/close()`` instead on your token, which has the same effect.
    @MainActor
    public func close(_ token: Token) {
        OpenCocoaWindowManager.shared[token]?.close()
    }
    
}

// MARK: - Window Manager

@MainActor
private final class OpenCocoaWindowManager {
    
    static let shared = OpenCocoaWindowManager()
    
    private lazy var windowControllers = [OpenCocoaWindowAction.Token: NSWindowController]()
    
    subscript(_ token: OpenCocoaWindowAction.Token) -> NSWindowController? {
        get { windowControllers[token] }
        set {
            windowControllers[token] = newValue
            
            if let newValue = newValue {
                openWindow(for: newValue, token: token)
            }
        }
    }
    
    private func openWindow(for controller: NSWindowController, token: OpenCocoaWindowAction.Token) {
        controller.window?.isReleasedWhenClosed = true
        controller.showWindow(nil)
        
        setupObservations(for: controller, token: token)
    }
    
    private func setupObservations(for controller: NSWindowController, token: OpenCocoaWindowAction.Token) {
        guard let window = controller.window else { return }
        
        NotificationCenter.default
            .publisher(for: NSWindow.willCloseNotification, object: window)
            .sink { [weak self] note in
                guard let self = self else { return }
                guard let window = note.object as? NSWindow else { return }
                
                self.handleWindowWillClose(window, token: token)
            }
            .store(in: &token.cancellables)
    }
    
    private func handleWindowWillClose(_ window: NSWindow, token: OpenCocoaWindowAction.Token) {
        token.isOpen = false
        
        windowControllers[token] = nil
    }
    
}

// MARK: - Token conformances

public extension OpenCocoaWindowAction.Token {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: OpenCocoaWindowAction.Token, rhs: OpenCocoaWindowAction.Token) -> Bool {
        lhs.id == rhs.id
    }
}
