//
//  InstallMethod.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 06/03/23.
//

import Foundation
import VirtualCore

enum InstallMethod: String, Identifiable, CaseIterable, Codable, ProvidesEmptyPlaceholder {
    var id: RawValue { rawValue }

    case remoteOptions
    case localFile
    case remoteManual

    static var empty: InstallMethod { .remoteOptions }
}

enum InstallMethodSelection: Identifiable, Hashable, Codable {
    case remoteOptions(RestoreImage)
    case localFile(URL)
    case remoteManual(URL)

    var id: InstallMethod {
        switch self {
        case .remoteOptions: .remoteOptions
        case .localFile: .localFile
        case .remoteManual: .remoteManual
        }
    }
}

extension InstallMethod {
    func description(for type: VBGuestType) -> String {
        switch self {
            case .localFile:
            switch type {
            case .mac:
                return "Open custom IPSW file from local storage"
            case .linux:
                return "Open custom ISO file from local storage"
            }
            case .remoteOptions:
                return "Download \(type.name) installer from a list of options"
            case .remoteManual:
                return "Download \(type.name) installer from a custom URL"
        }
    }

    var imageName: String {
        switch self {
            case .localFile:
                return "folder.fill"
            case .remoteOptions:
                return "square.and.arrow.down.fill"
            case .remoteManual:
                return "text.cursor"
        }
    }
}

extension VBGuestType {
    var customURLPrompt: String {
        switch self {
        case .mac:
            return "Enter the macOS IPSW URL"
        case .linux:
            return "Enter the Linux ISO URL"
        }
    }

    var restoreImagePickerPrompt: String {
        "Pick a \(name) Version to Install"
    }

    var installFinishedMessage: String {
        "Your \(name) Virtual Machine is Ready!"
    }
}
