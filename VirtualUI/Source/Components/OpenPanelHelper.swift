//
//  OpenPanelHelper.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI
import UniformTypeIdentifiers

public extension NSOpenPanel {

    static func run(accepting contentTypes: Set<UTType>, directoryURL: URL? = nil) -> URL? {
        let panel = NSOpenPanel()

        if contentTypes == [.folder] || contentTypes == [.directory] {
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        } else {
            panel.allowedContentTypes = Array(contentTypes)
        }

        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = directoryURL ?? URL(fileURLWithPath: NSHomeDirectory())

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        return url
    }

}
