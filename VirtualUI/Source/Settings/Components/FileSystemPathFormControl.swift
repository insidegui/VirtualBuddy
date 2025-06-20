import SwiftUI
import BuddyKit
import VirtualCore
import UniformTypeIdentifiers

struct FileSystemPathFormControl: View {
    var url: URL
    var contentTypes: Set<UTType>
    var defaultDirectoryKey: String
    var label: Text = Text("Location")
    var buttonLabel: Text = Text("Choose…")
    var setURL: (URL) -> ()

    @State private var isDraggingURL = false

    var body: some View {
        LabeledContent {
            HStack(alignment: .center, spacing: 4) {
                Text(url.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path)

                Button {
                    url.revealInFinder()
                } label: {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(.link)
                .foregroundStyle(Color.accentColor)
                .font(.subheadline.weight(.medium))
            }
        } label: {
            HStack {
                label

                Spacer()

                Button {
                    showOpenPanel()
                } label: {
                    buttonLabel
                }
                .controlSize(.small)
            }
        }
        .labeledContentStyle(.vertical)
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
        guard let newURL = NSOpenPanel.run(accepting: [.folder], directoryURL: url, defaultDirectoryKey: "library") else {
            return
        }

        guard newURL != url else { return }

        setURL(newURL)
    }
}
