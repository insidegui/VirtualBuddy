//
//  WHPayload.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 25/10/23.
//

import Foundation

/// Protocol adopted by types that can be sent over the guest <> host connection.
public protocol WHPayload: Codable {
    /// When `true`, the payload will be sent again if connection gets interrupted and re-established.
    static var resendOnReconnect: Bool { get }
}

public extension WHPayload {
    static var resendOnReconnect: Bool { false }
}
