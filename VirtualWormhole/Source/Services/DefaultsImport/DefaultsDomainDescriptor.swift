//
//  DefaultsDomainDescriptor.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 09/03/23.
//

import Cocoa
import UniformTypeIdentifiers

public struct DefaultsDomainDescriptor: Identifiable, Codable {
    public struct Target: Identifiable, Codable {
        public var id: String { bundleIdentifier }
        public var bundleIdentifier: String
        public var name: String
        public var isSystemApp: Bool
    }

    public struct Restart: Codable {
        public var command: String
        public var needsConfirmation = true
        public var shouldRelaunch = true
    }

    public var id: Target.ID { target.id }
    public var target: Target
    public var ignoredKeyPaths: [String] = []
    public var restart: Restart?
}

extension DefaultsDomainDescriptor.Target {
    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains(where: { !$0.isTerminated })
    }

    var bundleURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func iconImage(with size: CGSize = CGSize(width: 128, height: 128)) -> NSImage {
        func getIcon() -> NSImage {
            guard let url = bundleURL else {
                return NSWorkspace.shared.icon(for: .application)
            }

            return NSWorkspace.shared.icon(forFile: url.path)
        }

        let image = getIcon()
        image.size = size
        return image
    }
}
