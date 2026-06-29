import Foundation
import BuddyFoundation

extension VMImporter {
    func createBundle(forImportedVMPath path: FilePath, library: VMLibraryController) throws -> VBVirtualMachine {
        let name = path.lastComponentWithoutExtension

        let vmURL = library.libraryURL
            .appendingPathComponent(name)
            .appendingPathExtension(VBVirtualMachine.bundleExtension)

        guard !vmURL.isReadableDirectory else {
            throw "You already have a virtual machine named \(name.quoted). If you’d like to import this virtual machine from \(appName), please rename it first."
        }

        let model = VBVirtualMachine(bundleURL: vmURL)

        return model
    }
}
