import Foundation
import Virtualization
import BuddyKit

#if DEBUG
public final class SimulatedRestoreBackend: NSObject, RestoreBackend {
    public init(virtualMachine: VZVirtualMachine, restoringFromImageAt restoreImageFileURL: URL) {
        super.init()
    }

    public let progress = Progress(totalUnitCount: 100)

    private var timer: Timer?

    public func install(completionHandler: @escaping (Result<Void, any Error>) -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let count = progress.completedUnitCount + 1
            progress.completedUnitCount = count
            if count >= progress.totalUnitCount {
                timer?.invalidate()
                completionHandler(.success(()))
            }
        }
    }
}
#endif // DEBUG
