//
//  VBRestoreImageInfo.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/06/22.
//

import Foundation

public struct VBRestoreImageInfo: Identifiable, Decodable {
    public enum Channel: String, Decodable {
        case regular
        case developerBeta = "devbeta"
        case publicBeta = "pubbeta"
        case appleSeed = "seed"
    }

    public var id: String { build }
    public var name: String
    public var build: String
    public var channel: Channel
    public var url: URL
}
