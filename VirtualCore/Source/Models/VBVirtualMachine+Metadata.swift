//
//  VBVirtualMachine+Metadata.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 24/06/22.
//

import Cocoa

public extension VBVirtualMachine {

    func metadataDirectoryCreatingIfNeeded() throws -> URL {
        try metadataDirectoryURL.creatingDirectoryIfNeeded()
    }

    func write(_ data: Data, forMetadataFileNamed name: String) throws {
        let baseURL = try metadataDirectoryCreatingIfNeeded()

        let fileURL = baseURL.appendingPathComponent(name)

        try data.write(to: fileURL, options: .atomic)
    }

    func deleteMetadataFile(named name: String) throws {
        let fileURL = metadataDirectoryURL.appendingPathComponent(name)

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        try FileManager.default.removeItem(at: fileURL)
    }

    func metadataFileURL(_ fileName: String) -> URL {
        let fileURL = metadataDirectoryURL.appendingPathComponent(fileName)

        return fileURL
    }

    func metadataContents(_ fileName: String) -> Data? {
        let fileURL = metadataFileURL(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        return try? Data(contentsOf: fileURL)
    }

}

extension URL {
    func creatingDirectoryIfNeeded() throws -> Self {
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        }
        return self
    }
}

extension URL {
    /// `true` if URL points to a file contained within a VirtualBuddy VM bundle metadata directory.
    var isVirtualBuddyDataDirectoryFile: Bool {
        deletingLastPathComponent().lastPathComponent == VBVirtualMachine.metadataDirectoryName
    }

    var virtualMachineBundleParent: URL? {
        var current = self
        while current.pathExtension != VBVirtualMachine.bundleExtension {
            current = current.deletingLastPathComponent()
            guard current.path != "/" else { return nil }
        }
        return current
    }
}
