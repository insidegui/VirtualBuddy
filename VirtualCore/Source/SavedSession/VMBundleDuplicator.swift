import Foundation

/// Duplicates a virtual machine bundle so that the copy is either complete or doesn't exist.
///
/// The copy is built under a hidden name next to its destination, finished there, and only then moved into place.
/// A saved session is copied along with everything else, so the copy resumes independently from the original.
/// Temporary data from operations that were in progress on the original is never copied.
struct VMBundleDuplicator: Sendable {
    let fileSystem: SavedSessionFileSystem

    init(fileSystem: SavedSessionFileSystem = DefaultSavedSessionFileSystem()) {
        self.fileSystem = fileSystem
    }

    /// - Returns: The copy, with a new library identity but the same guest identity as the original.
    func duplicate(bundleAt sourceURL: URL, to destinationURL: URL) throws -> VBVirtualMachine {
        let workURL = destinationURL
            .deletingLastPathComponent()
            .appending(path: ".duplicating-\(UUID().uuidString).\(VBVirtualMachine.bundleExtension)", directoryHint: .isDirectory)

        do {
            try fileSystem.copy(from: sourceURL, to: workURL)

            for url in try fileSystem.contentsOfDirectory(at: workURL) where SavedSessionLayout.isTransientName(url.lastPathComponent) {
                try fileSystem.remove(url)
            }

            var copy = try VBVirtualMachine(bundleURL: workURL, isNewInstall: false, createIfNeeded: false)
            copy.uuid = UUID()
            try copy.saveMetadata()

            copy.bundleURL.creationDate = .now

            try fileSystem.move(from: workURL, to: destinationURL, replacingExisting: false)

            return try VBVirtualMachine(bundleURL: destinationURL, isNewInstall: false, createIfNeeded: false)
        } catch {
            try? fileSystem.remove(workURL)
            throw error
        }
    }
}
