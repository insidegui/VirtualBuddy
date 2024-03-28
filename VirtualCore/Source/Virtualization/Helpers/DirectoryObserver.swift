import Foundation
import Combine
import OSLog

final class DirectoryObserver: NSObject, NSFilePresenter {

    private let logger: Logger

    var presentedItemURL: URL?

    var presentedItemOperationQueue: OperationQueue = .main

    let signal: PassthroughSubject<URL, Never>
    let fileExtensions: Set<String>

    init(presentedItemURL: URL?, fileExtensions: Set<String>, label: String, signal: PassthroughSubject<URL, Never>) {
        self.logger = Logger(for: DirectoryObserver.self, label: label)
        self.presentedItemURL = presentedItemURL
        self.fileExtensions = fileExtensions
        self.signal = signal

        super.init()

        NSFileCoordinator.addFilePresenter(self)
    }

    private func sendSignalIfNeeded(for url: URL) {
        guard fileExtensions.contains(url.pathExtension) else { return }

        signal.send(url)
    }

    func presentedSubitemDidAppear(at url: URL) {
        logger.debug("Added: \(url.path)")

        sendSignalIfNeeded(for: url)
    }

    func presentedSubitemDidChange(at url: URL) {
        sendSignalIfNeeded(for: url)
    }

    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        logger.debug("Moved: \(oldURL.path) -> \(newURL.path)")

        sendSignalIfNeeded(for: newURL)
    }

    func accommodatePresentedSubitemDeletion(at url: URL) async throws {
        logger.debug("Deleted: \(url.path)")

        sendSignalIfNeeded(for: url)
    }

}
