import Foundation
import Virtualization
import BuddyKit
import Combine

@MainActor
public protocol RestoreBackend: AnyObject {
    init(model: VBVirtualMachine, restoringFromImageAt restoreImageFileURL: URL)
    var progress: Progress { get }
    func install() async throws
    func cancel() async
}

@MainActor
public protocol VirtualMachineProvidingRestoreBackend: RestoreBackend {
    var virtualMachine: AnyPublisher<VZVirtualMachine?, Never> { get }
}
