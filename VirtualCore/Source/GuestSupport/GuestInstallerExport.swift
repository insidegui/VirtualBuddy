import Foundation
import Observation
import OSLog

/// A user-requested export belongs to the VM session, not the transient popover
/// that started it. Its task retains this state until completion.
@MainActor @Observable
public final class GuestInstallerExport {
    public enum Phase: Equatable {
        case idle
        case choosingDestination
        case exporting
        case exported(URL)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "GuestInstallerExport")

    public var isBusy: Bool { phase == .choosingDestination || phase == .exporting }
    public var exportedURL: URL? {
        guard case .exported(let url) = phase else { return nil }
        return url
    }
    public var errorMessage: String? {
        guard case .failed(let message) = phase else { return nil }
        return message
    }

    public init() { }

    /// The destination chooser returns nil only when the user dismisses the save panel.
    /// Once accepted, every outcome is reported even if the initiating view disappears.
    @discardableResult
    public func start(
        chooseDestination: @escaping @MainActor () async -> URL?,
        export: @escaping @MainActor (URL) async throws -> Void,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) -> Task<Void, Never>? {
        guard !isBusy else { return nil }
        phase = .choosingDestination
        return Task {
            guard let destination = await chooseDestination() else {
                phase = .idle
                return
            }
            phase = .exporting
            logger.notice("Exporting guest installer to \(destination.path, privacy: .public)")
            do {
                try await export(destination)
                phase = .exported(destination)
                logger.notice("Guest installer exported to \(destination.path, privacy: .public)")
                completion(.success(destination))
            } catch {
                // There is no user-facing cancellation after the save panel.
                // Unexpected cancellation is an interruption, not silent success.
                let failure: Error
                if error is CancellationError {
                    failure = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: [
                        NSLocalizedDescriptionKey: "The guest installer export was interrupted. Please try again."
                    ])
                } else {
                    failure = error
                }
                phase = .failed(failure.localizedDescription)
                logger.error("Guest installer export failed: \(failure, privacy: .public)")
                completion(.failure(failure))
            }
        }
    }
}
