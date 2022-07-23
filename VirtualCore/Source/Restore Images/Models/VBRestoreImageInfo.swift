//
//  VBRestoreImageInfo.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/06/22.
//

import Foundation

public struct VBRestoreImageInfo: Hashable, Identifiable, Codable {
    public enum Channel: String, Codable {
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
    public var needsCookie: Bool
}

public extension VBRestoreImageInfo {

    struct AuthRequirement: Hashable, Identifiable {
        public var id: Channel.RawValue
        public var explainer: String
        public var signInURL: URL

        init(for channel: Channel) {
            self.id = channel.rawValue
            self.explainer = "Downloading this build requires access to the \(channel.portalName).\n\(channel.authenticationFootnote)"
            self.signInURL = channel.signInURL
        }
    }

    var authenticationRequirement: AuthRequirement? {
        guard needsCookie else { return nil }

        return AuthRequirement(for: channel)
    }

}

public extension VBRestoreImageInfo.AuthRequirement {

    func satisfiedCookieHeaderValue(with cookies: [HTTPCookie]) -> String? {
        let targetCookieNames = Set(["myacinfo", "aidshd", "DSESSIONID", "PHPSESSID", "dawsp", "aasp"])
        guard Set(cookies.map(\.name)).intersection(targetCookieNames) == targetCookieNames else { return nil }

        let formattedCookies = cookies.map({ "\($0.name)=\($0.value)" }).joined(separator: "; ")

        return formattedCookies
    }

}

extension VBRestoreImageInfo.Channel {

    var portalName: String {
        switch self {
            case .appleSeed:
                return "AppleSeed portal"
            case .publicBeta:
                return "Apple Beta portal"
            case .developerBeta:
                return "Apple Developer portal"
            default:
                return "¯\\_(ツ)_/¯"
        }
    }

    var authenticationFootnote: String {
        "Perform the authentication using the web view that will be opened. Your credentials will be sent directly to Apple and will not be stored locally or on any servers."
    }

    var signInURL: URL {
        switch self {
            case .appleSeed:
                return URL(string: "https://appleseed.apple.com/")!
            case .publicBeta:
                return URL(string: "https://beta.apple.com/")!
            default:
                return URL(string: "https://developer.apple.com/download")!
        }
    }

}
