import AppKit
import OSLog
import VirtualCore

@MainActor
final class HostFileDragCoordinator {
    private final class Session {
        let id = UUID()
        let sourceURLs: [URL]
        var latestLocation: VMHostFileDragLocation
        var hasBegunInGuest = false
        var dropRequested = false
        var isCancelled = false
        var lastUpdateDate = Date.distantPast
        var transferTask: Task<Void, Never>?

        init(sourceURLs: [URL], location: VMHostFileDragLocation) {
            self.sourceURLs = sourceURLs
            self.latestLocation = location
        }
    }

    private let logger = Logger(for: HostFileDragCoordinator.self)
    weak var controller: VMController?
    private var session: Session?

    func draggingEntered(_ draggingInfo: NSDraggingInfo, in view: NSView) -> NSDragOperation {
        cancelCurrentSession()

        guard let controller, controller.acceptsHostFileDrops else { return [] }
        guard let sourceURLs = fileURLs(from: draggingInfo), !sourceURLs.isEmpty else { return [] }

        let session = Session(
            sourceURLs: sourceURLs,
            location: normalizedLocation(of: draggingInfo, in: view)
        )
        self.session = session
        logger.notice(
            "Host file drag \(session.id, privacy: .public) entered with \(sourceURLs.count, privacy: .public) item(s) at \(session.latestLocation.x, privacy: .public), \(session.latestLocation.y, privacy: .public)"
        )

        session.transferTask = Task { [weak self, weak controller, weak session] in
            guard let self, let controller, let session else { return }

            do {
                try await controller.stageHostFiles(session.sourceURLs, for: session.id)
                guard self.session === session, !session.isCancelled else { return }

                session.hasBegunInGuest = true
                try await controller.beginHostFileDrag(session.id, at: session.latestLocation)
                self.logger.notice(
                    "Host file drag \(session.id, privacy: .public) begin sent at \(session.latestLocation.x, privacy: .public), \(session.latestLocation.y, privacy: .public)"
                )

                if session.dropRequested {
                    try await self.sendDrop(for: session, through: controller)
                }
            } catch is CancellationError {
                return
            } catch {
                self.logger.error("Host file transfer failed: \(error, privacy: .public)")
                guard self.session === session else { return }
                self.session = nil
                NSSound.beep()
            }
        }

        return .copy
    }

    func draggingUpdated(_ draggingInfo: NSDraggingInfo, in view: NSView) -> NSDragOperation {
        guard let session, !session.isCancelled else { return [] }

        session.latestLocation = normalizedLocation(of: draggingInfo, in: view)

        guard session.hasBegunInGuest,
              Date.now.timeIntervalSince(session.lastUpdateDate) >= 1.0 / 30.0,
              let controller
        else { return .copy }

        session.lastUpdateDate = .now
        let location = session.latestLocation
        Task {
            do {
                try await controller.updateHostFileDrag(session.id, location: location)
            } catch {
                self.logger.error(
                    "Host file drag \(session.id, privacy: .public) update failed: \(error, privacy: .public)"
                )
            }
        }

        return .copy
    }

    func draggingExited() {
        guard session?.dropRequested != true else { return }
        cancelCurrentSession()
    }

    func performDragOperation(_ draggingInfo: NSDraggingInfo, in view: NSView) -> Bool {
        guard let session, !session.isCancelled else { return false }

        session.latestLocation = normalizedLocation(of: draggingInfo, in: view)
        session.dropRequested = true
        logger.notice(
            "Host file drag \(session.id, privacy: .public) drop requested at \(session.latestLocation.x, privacy: .public), \(session.latestLocation.y, privacy: .public)"
        )

        if session.hasBegunInGuest, let controller {
            Task { [weak self, weak controller, weak session] in
                guard let self, let controller, let session else { return }
                do {
                    try await self.sendDrop(for: session, through: controller)
                } catch {
                    self.logger.error(
                        "Host file drag \(session.id, privacy: .public) drop failed: \(error, privacy: .public)"
                    )
                }
            }
        }

        return true
    }

    private func sendDrop(for session: Session, through controller: VMController) async throws {
        guard self.session === session, !session.isCancelled else { return }

        try await controller.dropHostFiles(session.id, at: session.latestLocation)
        logger.notice("Host file drag \(session.id, privacy: .public) drop sent")
        self.session = nil
    }

    private func cancelCurrentSession() {
        guard let session else { return }

        session.isCancelled = true
        session.transferTask?.cancel()
        self.session = nil
        logger.notice("Host file drag \(session.id, privacy: .public) cancelled")

        guard session.hasBegunInGuest, let controller else { return }
        Task {
            try? await controller.cancelHostFileDrag(session.id)
        }
    }

    private func fileURLs(from draggingInfo: NSDraggingInfo) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        return draggingInfo.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: options)?
            .compactMap { ($0 as? NSURL) as URL? }
    }

    private func normalizedLocation(of draggingInfo: NSDraggingInfo, in view: NSView) -> VMHostFileDragLocation {
        let point = view.convert(draggingInfo.draggingLocation, from: nil)
        guard view.bounds.width > 0, view.bounds.height > 0 else {
            return VMHostFileDragLocation(x: 0.5, y: 0.5)
        }

        return VMHostFileDragLocation(
            x: point.x / view.bounds.width,
            y: point.y / view.bounds.height
        )
    }
}
