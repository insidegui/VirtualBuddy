//
//  ConfigurationModels+Summary.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 19/07/22.
//

import Foundation

public extension VBMacConfiguration {

    var generalSummary: String {
        "\(hardware.cpuCount) CPUs / \(hardware.memorySize / 1024 / 1024 / 1024) GB"
    }

    var storageSummary: String {
        if hardware.storageDevices.count > 1 {
            return "\(hardware.storageDevices.count) Devices"
        } else {
            return "Boot Only"
        }
    }

    var displaySummary: String {
        guard let display = hardware.displayDevices.first else { return "No Displays" }
        return "\(display.width)x\(display.height)x\(display.pixelsPerInch)"
    }

    var soundSummary: String {
        guard let sound = hardware.soundDevices.first else { return "No Sound" }
        return sound.enableInput ? "Input / Output" : "Output Only"
    }

    var sharingSummary: String {
        let foldersSum: String
        if sharedFolders.count > 1 {
            foldersSum = "\(sharedFolders.count) Folders"
        } else if sharedFolders.isEmpty {
            foldersSum = ""
        } else {
            foldersSum = "One Folder"
        }

        #if ENABLE_SPICE_CLIPBOARD_SYNC
        if sharedClipboardEnabled {
            if foldersSum.isEmpty {
                return "Clipboard"
            } else {
                return "Clipboard / \(foldersSum)"
            }
        } else {
            return foldersSum.isEmpty ? "None" : foldersSum
        }
        #else
        return foldersSum.isEmpty ? "None" : foldersSum
        #endif
    }

    var networkSummary: String {
        guard let network = hardware.networkDevices.first else { return "No Network" }
        return network.kind.name
    }
    
    var pointingDeviceSummary: String { hardware.pointingDevice.kind.name }

    var nvramSummary: String { "\(hardware.NVRAM.count) Variables" }

}
