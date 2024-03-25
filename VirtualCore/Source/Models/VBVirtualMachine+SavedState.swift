import Foundation
import UniformTypeIdentifiers

public extension UTType {
    static let virtualBuddySavedState = UTType(
        exportedAs: "codes.rambo.VirtualBuddy.SavedState",
        conformingTo: .bundle
    )
}

public struct VBSavedStateMetadata: Identifiable, Hashable, Codable {
    public var id: String
    public var date: Date
}

public extension VBVirtualMachine {

    func savedStateDirectoryCreatingIfNeeded() throws -> URL {
        try savedStateDirectoryURL.creatingDirectoryIfNeeded()
    }

    func createSavedStatePackageURL() throws -> URL {
        let baseURL = try savedStateDirectoryCreatingIfNeeded()
        let suffix = DateFormatter.savedStateFileName.string(from: .now)
        let url = baseURL.appendingPathComponent("Save-\(suffix)", conformingTo: .virtualBuddySavedState)
        return try url.creatingDirectoryIfNeeded()
    }

    func savedStateDataFileURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent("State")
    }

    func savedStateMetadataFileURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent("Info", conformingTo: .propertyList)
    }

    static func virtualMachineURL(forSavedStatePackageURL url: URL) -> URL {
        url.deletingLastPathComponent().deletingLastPathComponent()
    }

}

private extension DateFormatter {
    static let savedStateFileName: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .init(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd_HH;mm;ss"
        return f
    }()
}
