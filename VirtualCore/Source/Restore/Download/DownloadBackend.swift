import Foundation
import Combine

public enum DownloadState: Hashable {
    case idle
    case preCheck(_ message: String)
    case downloading(_ progress: Double?, _ eta: Double?)
    case failed(_ error: String)
    case done(_ localURL: URL)
}

public protocol DownloadBackend: AnyObject {
    init(library: VMLibraryController, cookie: String?)
    var statePublisher: AnyPublisher<DownloadState, Never> { get }
    @MainActor func startDownload(with url: URL)
    @MainActor func cancelDownload()
}
