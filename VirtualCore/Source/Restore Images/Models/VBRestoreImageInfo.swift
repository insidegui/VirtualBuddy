//
//  VBRestoreImageInfo.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/06/22.
//

import Foundation
import BuddyFoundation

public struct VBGuestReleaseChannel: Hashable, Identifiable, Codable {
    public struct Authentication: Hashable, Identifiable, Codable {
        public var id: String { name }
        public var name: String
        public var url: URL
        public var note: String
    }

    public var id: String
    public var name: String
    public var note: String
    public var icon: String
    public var authentication: Authentication?

    public init(id: String, name: String, note: String, icon: String, authentication: Authentication? = nil) {
        self.id = id
        self.name = name
        self.note = note
        self.icon = icon
        self.authentication = authentication
    }
}

public struct VBGuestReleaseGroup: Hashable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var majorVersion: SoftwareVersion
    public var minHostVersion: SoftwareVersion

    public init(id: String, name: String, majorVersion: SoftwareVersion, minHostVersion: SoftwareVersion) {
        self.id = id
        self.name = name
        self.majorVersion = majorVersion
        self.minHostVersion = minHostVersion
    }
}

public struct VBRestoreImageInfo: Hashable, Identifiable, Codable {
    public var id: String { build }
    public var group: VBGuestReleaseGroup
    public var channel: VBGuestReleaseChannel
    public var name: String
    public var build: String
    public var url: URL
    @DecodableDefault.False
    public var needsCookie: Bool

    public init(group: VBGuestReleaseGroup, channel: VBGuestReleaseChannel, name: String, build: String, url: URL, needsCookie: Bool) {
        self.group = group
        self.channel = channel
        self.name = name
        self.build = build
        self.url = url
        self.needsCookie = needsCookie
    }
}

public extension VBRestoreImageInfo {

    var authenticationRequirement: VBGuestReleaseChannel.Authentication? {
        guard needsCookie else { return nil }

        return channel.authentication
    }

}

public extension VBGuestReleaseChannel.Authentication {

    func satisfiedCookieHeaderValue(with cookies: [HTTPCookie]) -> String? {
        let targetCookieNames = Set(["myacinfo", "aidshd", "DSESSIONID", "PHPSESSID", "dawsp", "aasp"])
        guard Set(cookies.map(\.name)).intersection(targetCookieNames) == targetCookieNames else { return nil }

        let formattedCookies = cookies.map({ "\($0.name)=\($0.value)" }).joined(separator: "; ")

        return formattedCookies
    }

}
