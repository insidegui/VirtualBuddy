import Foundation
import VirtualCore
import OSLog

final class GuestSharedFoldersManager: ObservableObject {

    private lazy var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Self.self))

    private let queue = DispatchQueue(label: "mount", qos: .userInitiated)

    @Published private(set) var error: Error?

    func mount() async throws {
        /// Virtualization's shared folders feature requires macOS 13.0.
        guard #available(macOS 13.0, *) else { return }

        logger.notice("Mount shared folders")

        let alreadyMounted = await checkAlreadyMounted()

        guard !alreadyMounted else {
            logger.notice("Shared folders already mounted, skipping mount")
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: Self.defaultMountPointURL.path) {
                logger.info("Shared folders mount point doesn't exist, creating at \(Self.defaultMountPointURL.path, privacy: .public)")

                try FileManager.default.createDirectory(at: Self.defaultMountPointURL, withIntermediateDirectories: true, attributes: nil)
            }

            try await runMount(with: [
                "-t",
                "virtiofs",
                VBSharedFolder.virtualBuddyShareName,
                Self.defaultMountPointURL.path
            ])
        } catch {
            logger.error("Mount shared folders failed with error: \(error, privacy: .public)")

            await MainActor.run {
                self.error = error
            }

            throw error
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.selectFile(Self.defaultMountPointURL.path, inFileViewerRootedAtPath: Self.defaultMountPointURL.deletingLastPathComponent().path)
    }

    private static let defaultMountPointURL: URL = {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop")
            .appendingPathComponent(VBSharedFolder.virtualBuddyShareName)
    }()

    /// `true` if the shared folder is already mounted.
    private func checkAlreadyMounted() async -> Bool {
        guard let mountPoints = (try? await runMount()).flatMap({ $0.components(separatedBy: .newlines) }) else {
            return false
        }

        logger.debug("Mount points: \(mountPoints.joined(separator: "\n"))")

        return mountPoints.contains { $0.contains(Self.defaultMountPointURL.path) }
    }

    @discardableResult
    private func runMount(with arguments: [String] = []) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/sbin/mount")
                proc.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                do {
                    try proc.run()
                    proc.waitUntilExit()

                    if proc.terminationStatus == 0 {
                        let output = (try? outPipe.fileHandleForReading.readToEnd()).flatMap({ String(decoding: $0, as: UTF8.self) })
                        continuation.resume(returning: output ?? "")
                    } else {
                        continuation.resume(throwing: CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Mount command failed with code \(proc.terminationStatus)."]))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

}
