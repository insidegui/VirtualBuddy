import Foundation
import Virtualization
import BuddyKit

@MainActor
public protocol RestoreBackend: AnyObject {
    init(model: VBVirtualMachine, restoringFromImageAt restoreImageFileURL: URL)
    var progress: Progress { get }
    func install() async throws
}
