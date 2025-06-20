//
//  OpenVirtualBuddySettingsAction.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/06/25.
//

import SwiftUI
import VirtualCore
import DeepLinkSecurity
import BuddyKit

public struct OpenVirtualBuddySettingsAction {
    public var run: @MainActor () -> ()

    public init(run: @escaping @MainActor () -> () = { preconditionFailure("Missing openVirtualBuddySettings in environment.") }) {
        self.run = run
    }

    @MainActor
    public func callAsFunction() {
        run()
    }
}

public extension EnvironmentValues {
    @Entry var openVirtualBuddySettings = OpenVirtualBuddySettingsAction()
}
