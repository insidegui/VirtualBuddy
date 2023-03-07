//
//  VBRestoreImagesResponse.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/06/22.
//

import Foundation

struct VBRestoreImagesResponse: Decodable {
    let success: Bool
    let error: String?
    let channels: [VBGuestReleaseChannel]
    let groups: [VBGuestReleaseGroup]
    let images: [VBRestoreImageInfo]
}

