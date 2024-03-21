import SwiftUI
import UniformTypeIdentifiers
import OSLog

private let logger = Logger(subsystem: VirtualUIConstants.subsystemName, category: "OpenSavePanelUtils")

public extension NSOpenPanel {

    static func run(accepting contentTypes: Set<UTType>, directoryURL: URL? = nil, defaultDirectoryKey: String? = nil) -> URL? {
        let panel = NSOpenPanel()

        if contentTypes == [.folder] || contentTypes == [.directory] {
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        } else {
            panel.allowedContentTypes = Array(contentTypes)
        }

        panel.treatsFilePackagesAsDirectories = true

        let defaultsKey = defaultDirectoryKey.flatMap { "defaultDirectory-\($0)" }

        if let defaultsKey, let defaultDirectoryPath = UserDefaults.standard.string(forKey: defaultsKey) {
            panel.directoryURL = URL(fileURLWithPath: defaultDirectoryPath)
        } else if let directoryURL {
            panel.directoryURL = directoryURL
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        if let defaultsKey {
            /// If user is choosing a folder, then just store the path to the folder itself.
            /// If user is choosing files, then remove the last path component to save the path to the file's directory instead.
            let effectiveURL = contentTypes.contains(.folder) ? url : url.deletingLastPathComponent()
            UserDefaults.standard.set(effectiveURL.path, forKey: defaultsKey)
        }

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
