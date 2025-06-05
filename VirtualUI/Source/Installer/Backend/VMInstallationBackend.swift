import Foundation
import Virtualization
import VirtualCore
import BuddyKit

protocol VMInstallationBackend: AnyObject {
    init(virtualMachine: VZVirtualMachine, restoringFromImageAt restoreImageFileURL: URL)
    func install(completionHandler: @escaping (Result<Void, any Error>) -> Void)
    var progress: Progress { get }
}

extension VZMacOSInstaller: VMInstallationBackend { }

final class SimulatedVMInstallationBackend: NSObject, VMInstallationBackend {
    init(virtualMachine: VZVirtualMachine, restoringFromImageAt restoreImageFileURL: URL) {
        super.init()
    }

    let progress = Progress(totalUnitCount: 100)

    private var timer: Timer?

    func install(completionHandler: @escaping (Result<Void, any Error>) -> Void) {
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
