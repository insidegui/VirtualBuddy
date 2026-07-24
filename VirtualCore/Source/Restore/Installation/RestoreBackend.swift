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

public struct RestoreFailure: LocalizedError, Sendable {
    public let message: String
    public let diagnosticFileURLs: [URL]

    public var errorDescription: String? { message }

    public init(message: String, diagnosticFileURLs: [URL]) {
        self.message = message
        self.diagnosticFileURLs = diagnosticFileURLs
    }
}
