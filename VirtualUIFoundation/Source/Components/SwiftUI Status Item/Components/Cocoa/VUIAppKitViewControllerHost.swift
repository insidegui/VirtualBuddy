import Cocoa
import SwiftUI

/// A SwiftUI view that hosts any AppKit view controller so that it can be presented in a
/// context that requires the contents to be SwiftUI views, such as with ``StatusItemManager``.
struct VUIAppKitViewControllerHost<ChildController>: NSViewControllerRepresentable where ChildController: NSViewController {

    typealias NSViewControllerType = _VUIViewControllerHostingController<ChildController>

    private let contentControllerBuilder: () -> ChildController

    init(with contentController: @escaping @autoclosure () -> ChildController) {
        self.contentControllerBuilder = contentController
    }

    func makeNSViewController(context: Context) -> NSViewControllerType {
        let host = _VUIViewControllerHostingController(with: contentControllerBuilder)
        return host
    }

    func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context) {

    }

}

final class _VUIViewControllerHostingController<ChildController>: NSViewController where ChildController: NSViewController {

    private let contentControllerBuilder: () -> ChildController

    fileprivate init(with contentController: @escaping () -> ChildController) {
        self.contentControllerBuilder = contentController

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        let contentController = contentControllerBuilder()

        addChild(contentController)
        contentController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentController.view)

        NSLayoutConstraint.activate([
            contentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

}
