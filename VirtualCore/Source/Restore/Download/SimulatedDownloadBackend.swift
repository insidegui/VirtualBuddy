import Foundation
import Combine

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
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }

            progress += 0.01

            if progress >= 1.0 {
                stateSubject.send(.done(Self.localFileURL))
            } else {
                stateSubject.send(.downloading(progress, progress >= 0.15 ? 100 - progress * 100 : 0))
            }
        }
        self.timer = timer

        /// Schedule timer manually so that it's not blocked by modal dialogs or event tracking.
        RunLoop.main.add(timer, forMode: .common)
    }

    public func cancelDownload() {
        stateSubject.send(.failed("Cancelled."))
    }
}
#endif // DEBUG
