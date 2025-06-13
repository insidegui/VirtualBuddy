import Foundation
import BuddyFoundation
import UniformTypeIdentifiers

/// Adopted by types that can import virtual machines from other apps.
@MainActor
public protocol VMImporter {
    /// The name of the app that this importer can import VM bundles from.
    var appName: String { get }

    /// The UTI for the virtual machine bundle that can be imported by this importer.
    var fileType: UTType { get }

    /// Performs all actions required to convert the virtual machine from the other app into VirtualBuddy, including copying it into the user's library.
    ///
    /// - note: Importers don't need to call `saveMetadata` on the VM model, this is done automatically after a successful import.
    @discardableResult
    func importVirtualMachine(from path: FilePath, into library: VMLibraryController) async throws -> VBVirtualMachine
}
