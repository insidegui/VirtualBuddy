//
//  VBMacDevice+Storage.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 20/07/22.
//

import Foundation

public extension VBMacDevice {

    mutating func addOrUpdate(_ storage: VBStorageDevice) {
        if let idx = storageDevices.firstIndex(where: { $0.id == storage.id }) {
            storageDevices[idx] = storage
        } else {
            storageDevices.append(storage)
        }
    }

}
