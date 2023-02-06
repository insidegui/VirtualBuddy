import Cocoa

final class StatusItemPanelContentController: NSViewController {

    let child: NSViewController
    var onContentSizeChange: ((CGSize) -> Void)?

    init(child: NSViewController, onContentSizeChange: ((CGSize) -> Void)? = nil) {
        self.child = child
        self.onContentSizeChange = onContentSizeChange

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)

        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: StatusBarPanelChromeMetrics.shadowPadding),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -StatusBarPanelChromeMetrics.shadowPadding),
            child.view.topAnchor.constraint(equalTo: view.topAnchor, constant: StatusBarPanelChromeMetrics.shadowPadding),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -StatusBarPanelChromeMetrics.shadowPadding),
        ])
    }

    var contentSize: CGSize { view.bounds.size }

    private var previouslyReportedSize: CGSize = .zero

    override func viewDidLayout() {
        super.viewDidLayout()

        let newSize = view.bounds.size

        guard newSize != previouslyReportedSize else { return }

        previouslyReportedSize = newSize

        self.onContentSizeChange?(newSize)
    }

}
