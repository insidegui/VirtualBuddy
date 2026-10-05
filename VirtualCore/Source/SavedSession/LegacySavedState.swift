import Foundation
import UniformTypeIdentifiers

public extension UTType {
    /// Named saved states (`.vbst`) created by earlier versions of VirtualBuddy.
    ///
    /// They can't be resumed safely: they never captured the disks as they were when the state was saved.
    /// They're left exactly as they are, and the app only offers to show them in Finder.
    static let virtualBuddySavedState = UTType(
        exportedAs: "codes.rambo.VirtualBuddy.SavedState",
        conformingTo: .bundle
    )
}
