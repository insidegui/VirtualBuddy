import Foundation
import Combine

public enum DownloadState: Hashable {
    case idle
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

#if DEBUG
public final class SimulatedDownloadBackend: NSObject, DownloadBackend {
    public static let localFileURL = Bundle.virtualCore.url(forResource: "FakeRestoreImage", withExtension: "ipsw")!

    public init(library: VMLibraryController, cookie: String?) {
        super.init()
    }

    public var statePublisher: AnyPublisher<DownloadState, Never> { stateSubject.eraseToAnyPublisher() }

    private let stateSubject = PassthroughSubject<DownloadState, Never>()

    private var timer: Timer?

    private var progress: Double = 0

    public func startDownload(with url: URL) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }

            progress += 0.05

            if progress >= 1.0 {
                stateSubject.send(.done(Self.localFileURL))
            } else {
                stateSubject.send(.downloading(progress, progress >= 0.15 ? 100 - progress * 100 : 0))
            }
        }
    }

    public func cancelDownload() {
        stateSubject.send(.failed("Cancelled."))
    }
}
#endif // DEBUG
