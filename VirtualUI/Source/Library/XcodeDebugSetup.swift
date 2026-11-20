import AppKit
import SwiftUI
import Combine
import VirtualCore

@MainActor
public enum XcodeDebugSetup {
    private static var observer: AnyCancellable?
    private static var window: NSPanel?
    public static func observeCachePreparation() {
        observer = DebugSymbolCache.shared.$activities.map { !$0.isEmpty }.removeDuplicates().receive(on: RunLoop.main).sink { preparing in
            if preparing {
                let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 420, height: 150), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                panel.title = "Preparing Xcode Debugging Symbols"
                panel.contentView = NSHostingView(rootView: DebugCacheProgress())
                panel.center()
                panel.orderFrontRegardless()
                window = panel
            } else {
                window?.orderOut(nil)
                window = nil
            }
        }
    }
}

private struct DebugCacheProgress: View {
    @ObservedObject private var cache = DebugSymbolCache.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(cache.activities) { activity in
                Text("macOS " + activity.system).font(.headline)
                ProgressView(value: activity.fraction) { Text(activity.detail) }
                Button("Cancel") { cache.cancel(activity.id) }
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
}

struct DebugCacheSettings: View {
    @ObservedObject private var cache = DebugSymbolCache.shared
    var body: some View {
        Section("Xcode Debugging Symbols") {
            if cache.entries.isEmpty {
                Text("No cached guest symbols").foregroundStyle(.secondary)
            }
            ForEach(cache.entries) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text("macOS " + entry.system)
                        Text(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Delete") {
                        do { try cache.remove(entry) } catch { NSApp.presentError(error) }
                    }.disabled(cache.isInUse(entry))
                }
            }
        }.onAppear { cache.reload() }
    }
}
