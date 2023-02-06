import Foundation
import VirtualCore

final class GuestSharedFoldersManager: ObservableObject {

    private let queue = DispatchQueue(label: "mount", qos: .userInitiated)

    @Published private(set) var error: Error?

    func mount() async throws {
        /// Virtualization's shared folders feature requires macOS 13.0.
        guard #available(macOS 13.0, *) else { return }

        do {
            if !FileManager.default.fileExists(atPath: Self.defaultMountPointURL.path) {
                try FileManager.default.createDirectory(at: Self.defaultMountPointURL, withIntermediateDirectories: true, attributes: nil)
            }

            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/sbin/mount")
                    proc.arguments = [
                        "-t",
                        "virtiofs",
                        VBSharedFolder.virtualBuddyShareName,
                        Self.defaultMountPointURL.path
                    ]
                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    proc.standardOutput = outPipe
                    proc.standardError = errPipe

                    do {
                        try proc.run()
                        proc.waitUntilExit()

                        if proc.terminationStatus == 0 {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Mount command failed with code \(proc.terminationStatus)."]))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
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

}
