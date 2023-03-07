//
//  GuestAdditionsDiskImage.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/03/23.
//

import Foundation
import Virtualization

extension VZVirtioBlockDeviceConfiguration {

    static let guestAdditionsDiskImageName: String = {
        #if DEBUG
        return "VirtualBuddyGuest-Debug"
        #else
        return "VirtualBuddyGuest"
        #endif
    }()

    static var guestAdditionsDisk: VZVirtioBlockDeviceConfiguration {
        get throws {
            guard let guestImageURL = Bundle.main.url(forResource: Self.guestAdditionsDiskImageName, withExtension: "dmg") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Missing \(Self.guestAdditionsDiskImageName).dmg in the app's resources."])
            }

            let guestAttachment = try VZDiskImageStorageDeviceAttachment(url: guestImageURL, readOnly: true)

            return VZVirtioBlockDeviceConfiguration(attachment: guestAttachment)
        }
    }

}
