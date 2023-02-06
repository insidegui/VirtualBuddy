import Cocoa
import SwiftUI

protocol StatusItemProvider: ObservableObject {
    /// `true` when the background of the status item's view should be highlighted.
    var isStatusItemHighlighted: Bool { get }

    var isStatusItemOccluded: Bool { get }

    /// Show/hide the status item's content panel.
    func togglePanelVisible()

    /// Show a pop up menu produced by running the builder closure.
    func showPopUpMenu(using builder: () -> NSMenu)
}
