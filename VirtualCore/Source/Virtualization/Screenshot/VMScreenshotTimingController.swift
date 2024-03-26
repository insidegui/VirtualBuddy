import Foundation

/// Provides scheduling for periodic VM screenshots.
/// This is used by `VMScreenshotter` in `VirtualUI`.
public final class VMScreenshotTimingController {
    private var timer: Timer?

    public let interval: TimeInterval
    private let onTimerFired: () async throws -> Void

    public init(interval: TimeInterval, onTimerFired: @escaping () async throws -> Void) {
        assert(interval > 1, "The minimum interval is 1 second")

        self.interval = max(1, interval)
        self.onTimerFired = onTimerFired
    }

    public func activate() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { [weak self] _ in
            self?.timerFired()
        })
    }

    public func invalidate() {
        pendingTask?.cancel()
        pendingTask = nil

        timer?.invalidate()
        timer = nil
    }

    private var pendingTask: Task<(), Error>?

    private func timerFired() {
        pendingTask?.cancel()

        pendingTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            try await self.onTimerFired()
        }
    }

    deinit {
        #if DEBUG
        print("\(String(describing: self)) 👋🏻")
        #endif
    }
}
