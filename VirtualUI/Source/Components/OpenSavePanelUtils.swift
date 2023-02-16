import SwiftUI
import UniformTypeIdentifiers
import OSLog

private let logger = Logger(subsystem: VirtualUIConstants.subsystemName, category: "OpenSavePanelUtils")

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
        panel.directoryURL = directoryURL

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        return url
    }

}

public extension NSSavePanel {

    static func run(for contentTypes: Set<UTType>, directoryURL: URL? = nil) -> URL? {
        let panel = NSSavePanel()

        panel.allowedContentTypes = Array(contentTypes)

        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = directoryURL

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        return url
    }

    static func run(saving data: Data, as contentType: UTType, directoryURL: URL? = nil) {
        guard let url = run(for: [contentType], directoryURL: directoryURL) else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

}
