import Foundation
import OSLog

/// Duplicates a virtual machine bundle so that the copy is either complete or doesn't exist.
///
/// The copy is built under a hidden name next to its destination, finished there, and only then moved into place.
/// A saved session is copied along with everything else, so the copy resumes independently from the original.
/// Temporary data from operations that were in progress on the original is never copied, with one exception:
/// a saved session that was interrupted after it was resumed keeps that fact in the copy. The copy's disks may be newer than
/// the session, so resuming the copy has to ask first, exactly like the original.
///
/// Settings that the user approved for the original are approved again for the copy, because duplicating is something
/// the user does in VirtualBuddy. A bundle copied by any other means has to have those settings reviewed.
struct VMBundleDuplicator: Sendable {
    typealias ApprovalCarrier = @Sendable (_ original: VBVirtualMachine, _ copy: VBVirtualMachine) throws -> Void

    let fileSystem: SavedSessionFileSystem
    let carryApprovals: ApprovalCarrier

    private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "VMBundleDuplicator")

    init(fileSystem: SavedSessionFileSystem = DefaultSavedSessionFileSystem(),
         carryApprovals: @escaping ApprovalCarrier = { try VBVirtualMachine.carryApprovedSettings(from: $0, to: $1) }) {
        self.fileSystem = fileSystem
        self.carryApprovals = carryApprovals
    }

    /// - Returns: The copy, with a new library identity but the same guest identity as the original.
    func duplicate(bundleAt sourceURL: URL, to destinationURL: URL) throws -> VBVirtualMachine {
        let workURL = destinationURL
            .deletingLastPathComponent()
            .appending(path: ".duplicating-\(UUID().uuidString).\(VBVirtualMachine.bundleExtension)", directoryHint: .isDirectory)

        do {
            /// Operations that were interrupted before the virtual machine could have run are finished (rolled back) on the original first,
            /// so that the copy never starts from files that are halfway through being replaced. What's left is only
            /// the record of a session that was resumed, which the copy has to keep.
            try SavedSessionStorage(bundleURL: sourceURL, fileSystem: fileSystem).recover()

            try fileSystem.copy(from: sourceURL, to: workURL)

            for url in try fileSystem.contentsOfDirectory(at: workURL) {
                let name = url.lastPathComponent
                guard SavedSessionLayout.isTransientName(name), name != SavedSessionLayout.transactionName else { continue }
                try fileSystem.remove(url)
            }

            var copy = try VBVirtualMachine(bundleURL: workURL, isNewInstall: false, createIfNeeded: false)
            copy.uuid = UUID()
            try copy.saveMetadata()

            copy.bundleURL.creationDate = .now

            try fileSystem.move(from: workURL, to: destinationURL, replacingExisting: false)
        } catch {
            try? fileSystem.remove(workURL)
            throw error
        }

        let duplicate = try VBVirtualMachine(bundleURL: destinationURL, isNewInstall: false, createIfNeeded: false)

        /// The copy is complete and usable at this point. Without its approvals it only asks for them to be reviewed,
        /// which is not worth failing the duplication for.
        do {
            let original = try VBVirtualMachine(bundleURL: sourceURL, isNewInstall: false, createIfNeeded: false)
            try carryApprovals(original, duplicate)
        } catch {
            logger.error("Unable to carry approved settings over to \(destinationURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        return duplicate
    }
}
