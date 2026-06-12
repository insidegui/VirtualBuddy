import SwiftUI
import VirtualCore
import UniformTypeIdentifiers

struct LogConsole: View {

    static var padding: CGFloat { 16 }

    @StateObject private var streamer: LogStreamer

    init(predicate: LogStreamer.Predicate) {
        self._streamer = .init(wrappedValue: LogStreamer(predicate: predicate))
    }

    init(streamer: LogStreamer) {
        self._streamer = .init(wrappedValue: streamer)
    }

    @State private var searchTerm = ""
    @AppStorage("LogConsole.ScrollAutomatically") private var autoscroll = true

    private var filteredEvents: [LogEntry] {
        guard searchTerm.count >= 3 else { return streamer.events }
        return streamer.events.filter {
            $0.message.localizedCaseInsensitiveContains(searchTerm)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredEvents) { entry in
                        Text(entry.formattedTime + " ")
                            .foregroundColor(.secondary)
                        + Text(entry.message)
                            .foregroundColor(entry.level.color)
                    }

                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .font(.system(.body).monospaced())
                .textSelection(.enabled)
            }
            .onChange(of: filteredEvents.count) {
                guard autoscroll else { return }
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
            .onChange(of: autoscroll) { oldValue, newValue in
                guard !oldValue, newValue else { return }
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
            .virtualBuddyBottomBar { bottomBar }
            .overlay(alignment: .topTrailing) {
                Toggle(isOn: $autoscroll) {
                    Label("Scroll automatically", systemImage: "chevron.up.chevron.down")
                        .labelStyle(.iconOnly)
                        .padding(3)
                }
                .toggleStyle(.button)
                .airGlassButtonStyle()
                .buttonBorderShape(.circle)
                .help("Scroll automatically")
                .padding([.top, .trailing], Self.padding)
            }
        }
        .onAppear(perform: streamer.activate)
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
            .textFieldStyle(.plain)
    }

    private var fullLogText: String {
        filteredEvents
            .map(\.description)
            .joined(separator: "\n")
    }

    @ViewBuilder
    private var bottomBar: some View {
        AirGlassEffectContainer {
            HStack {
                searchField
                    .frame(height: 32)
                    .frame(maxWidth: 240)
                    .padding(.horizontal, 14)
                    .airMaterialBackground(visualEffect: .menu, glassEffect: .regular, in: Capsule())

                Spacer()

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
                .frame(height: 32)
                .padding(.horizontal, 14)
                .airMaterialBackground(visualEffect: .menu, glassEffect: .regular, in: Capsule())
            }
        }
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
