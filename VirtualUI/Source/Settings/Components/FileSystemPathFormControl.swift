import SwiftUI
import AppKit
import BuddyUI
import VirtualCore
import UniformTypeIdentifiers

struct FileSystemPathFormControl: View {
    var url: URL
    var contentTypes: Set<UTType>
    var defaultDirectoryKey: String
    var setURL: (URL) -> ()

    @State private var isDraggingURL = false

    var body: some View {
        HStack(spacing: 8) {
            Text(url.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(url.path)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reveal in Finder")
            .help("Reveal in Finder")

            Button("Choose…", action: showOpenPanel)
                .fixedSize()
        }
        .dropDestination(for: URL.self) { items, _ in
            guard items.count == 1 else { return false }
            guard let type = FilePath(items[0]).contentType else { return false }
            guard contentTypes.contains(where: { type.conforms(to: $0) }) else { return false }

            setURL(items[0])

            return true
        } isTargeted: {
            isDraggingURL = $0
        }
        .background {
            if isDraggingURL {
                Color.accentColor
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(-10)
                    .opacity(0.4)
            }
        }
    }

    private func showOpenPanel() {
        guard let newURL = NSOpenPanel.run(accepting: contentTypes, directoryURL: url, defaultDirectoryKey: defaultDirectoryKey) else {
            return
        }

        guard newURL != url else { return }

        setURL(newURL)
    }
}
