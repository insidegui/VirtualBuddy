import SwiftUI
import VirtualCore
import UniformTypeIdentifiers

struct LogConsole: View {
    
    @StateObject private var streamer: LogStreamer

    init(predicate: LogStreamer.Predicate) {
        self._streamer = .init(wrappedValue: LogStreamer(predicate: predicate))
    }

    init(streamer: LogStreamer) {
        self._streamer = .init(wrappedValue: streamer)
    }

    @State private var searchTerm = ""

    private var filteredEvents: [LogEntry] {
        guard searchTerm.count >= 3 else { return streamer.events }
        return streamer.events.filter {
            $0.message.localizedCaseInsensitiveContains(searchTerm)
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(filteredEvents) { entry in
                    Text(entry.formattedTime + " ")
                        .foregroundColor(.secondary)
                    + Text(entry.message)
                        .foregroundColor(entry.level.color)
                }
            }
            .font(.system(.body).monospaced())
            .padding(.horizontal)
            .padding(.top, 6)
            .textSelection(.enabled)
        }
        .safeAreaInset(edge: .top, content: { searchBar })
        .safeAreaInset(edge: .bottom, content: { bottomBar })
        .onAppear(perform: streamer.activate)
    }

    @ViewBuilder
    private var searchBar: some View {
        ZStack {
            searchField
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Material.thick, in: Rectangle())
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @FocusState private var searchFieldFocused: Bool

    @ViewBuilder
    private var searchField: some View {
        TextField("Search Logs", text: $searchTerm)
            .focused($searchFieldFocused)
            .onExitCommand {
                if searchTerm == "" { searchFieldFocused = false }
                searchTerm = ""
            }
            .textFieldStyle(.roundedBorder)
    }

    private var fullLogText: String {
        filteredEvents
            .map(\.description)
            .joined(separator: "\n")
    }

    @ViewBuilder
    private var bottomBar: some View {
        ZStack {
            HStack(spacing: 16) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullLogText, forType: .string)
                } label: {
                    Text("Copy Text")
                }

                Button {
                    NSSavePanel.run(saving: Data(fullLogText.utf8), as: .logFile)
                } label: {
                    Text("Save to File…")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .controlGroup(Capsule(style: .continuous), level: .secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .bottomTrailing)
        .controlSize(.small)
        .buttonStyle(.link)
    }
}

extension LogEntry.Level {
    var color: Color {
        switch self {
        case .debug:
            return .gray.opacity(0.6)
        case .trace:
            return .gray.opacity(0.8)
        case .notice:
            return .gray.opacity(0.9)
        case .info:
            return .gray
        case .default:
            return .primary
        case .warning:
            return .yellow
        case .error:
            return .orange
        case .fault:
            return .red
        case .critical:
            return Color(nsColor: .magenta)
        }
    }
}

#if DEBUG
struct LogConsole_Previews: PreviewProvider {
    static var previews: some View {
        LogConsole(streamer: .preview)
    }
}
#endif

extension UTType {
    static let logFile: UTType = {
        UTType(filenameExtension: "log", conformingTo: .log) ?? .plainText
    }()
}
