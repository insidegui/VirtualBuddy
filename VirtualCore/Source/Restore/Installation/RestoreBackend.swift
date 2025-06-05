import Foundation
import Virtualization
import BuddyKit

public protocol RestoreBackend: AnyObject {
    init(virtualMachine: VZVirtualMachine, restoringFromImageAt restoreImageFileURL: URL)
    func install(completionHandler: @escaping (Result<Void, any Error>) -> Void)
    var progress: Progress { get }
}

extension VZMacOSInstaller: RestoreBackend { }
