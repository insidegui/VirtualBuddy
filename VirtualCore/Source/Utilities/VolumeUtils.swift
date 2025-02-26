//
//  VolumeUtils.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 20/07/22.
//

import Foundation

public extension VBSettingsContainer {

    /// Returns `true` if the VirtualBuddy library seems to be in an APFS volume.
    var isLibraryInAPFSVolume: Bool { settings.libraryURL.hasAPFSIdentifier }

    /// Returns `true` if the volume where the VirtualBuddy library resides has enough
    /// free space to fit the given amount of bytes.
    /// If checking the free disk space fails, this falls back to returning `true`.
    func libraryVolumeCanFit(_ size: UInt64) -> Bool {
        guard let freeSize = settings.libraryURL.freeDiskSpaceOnVolume else { return true }
        return Int64(freeSize) - Int64(size) > 0
    }

}

public extension VMLibraryController {
    /// Whether this library is stored in an APFS volume.
    var isInAPFSVolume: Bool { libraryURL.hasAPFSIdentifier }
}

public extension URL {

    /// Checks if the item at the URL contains an APFS content identifier, as a way to check for
    /// whether the containing volume is an APFS volume.
    var hasAPFSIdentifier: Bool {
        #if DEBUG
        guard !UserDefaults.standard.bool(forKey: "VBSimulateNonAPFSVolume") else { return false }
        #endif

        guard let values = try? resourceValues(forKeys: [.fileContentIdentifierKey]),
              values.fileContentIdentifier != nil
        else {
            return false
        }

        return true
    }

    /// The free disk space in the volume that contains this URL.
    var freeDiskSpaceOnVolume: UInt64? {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            guard let freeSize = attrs[.systemFreeSize] as? UInt64 else { return nil }
            return freeSize
        } catch {
            return nil
        }
    }

    /// User-friendly name for the volume that contains this URL.
    var containingVolumeName: String? {
        guard let volumeURL = (try? resourceValues(forKeys: [.volumeURLKey]))?.volume else { return nil }

        guard let values = try? volumeURL.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeNameKey]) else { return nil }

        if let localizedName = values.volumeLocalizedName {
            return localizedName
        } else if let name = values.volumeName {
            return name
        } else {
            return volumeURL.lastPathComponent
        }
    }

    /// `true` if the URL is contained in a volume that's not internal.
    var residesInExternalVolume: Bool {
        (try? resourceValues(forKeys: [.volumeIsInternalKey]))?.volumeIsInternal == false
    }

    /// Returns the URL for the external volume that contains this URL.
    /// Returns `nil` if the URL resides in internal storage, or if the volume couldn't be determined.
    var externalVolumeURL: URL? {
        guard residesInExternalVolume else { return nil }
        return try? resourceValues(forKeys: [.volumeURLKey]).volume
    }
    
}
