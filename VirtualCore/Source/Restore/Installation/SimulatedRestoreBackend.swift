import Foundation
import Virtualization
import BuddyKit
import Combine

#if DEBUG
public final class SimulatedRestoreBackend: NSObject, RestoreBackend, @unchecked Sendable {
    public init(model: VBVirtualMachine, restoringFromImageAt restoreImageFileURL: URL) {
        super.init()
    }

    public let progress = Progress(totalUnitCount: 100)

    private var timer: Timer?

    private var cancellable: AnyCancellable?

    public func install() async throws {
        await withCheckedContinuation { continuation in
            cancellable = Timer.publish(every: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }

                    let count = progress.completedUnitCount + 1
                    progress.completedUnitCount = count

                    if count >= progress.totalUnitCount {
                        MainActor.assumeIsolated {
                            self.timer?.invalidate()
                            self.cancellable = nil
                        }

                        continuation.resume()
                    }
                }
        }
    }
}
#endif // DEBUG
