import Foundation
import Virtualization
import Combine

@MainActor
public protocol RestoreBackend: AnyObject {
    init(model: VBVirtualMachine, restoringFromImageAt restoreImageFileURL: URL)
    var progress: Progress { get }
    func install() async throws
    func cancel() async
    var consolePredicate: LogStreamer.Predicate { get }
}

@MainActor
public protocol VirtualMachineProvidingRestoreBackend: RestoreBackend {
    var virtualMachine: AnyPublisher<VZVirtualMachine?, Never> { get }
}
