import AppKit
import SwiftUI
import Combine
import VirtualCore
import MacDebugHost

@MainActor
public enum XcodeDebugSetup {
    private static var observer: AnyCancellable?
    private static var panels: [UUID: XcodeRunPanel] = [:]

    public static func observeCachePreparation() {
        observer = VirtualBuddyDebugging.symbolCache.$activities
            .removeDuplicates { $0.map(\.id) == $1.map(\.id) }
            .receive(on: RunLoop.main)
            .sink { activities in
                let active = Set(activities.map(\.id))
                for (id, panel) in panels where !active.contains(id) {
                    panel.dismiss()
                    panels[id] = nil
                }
                for activity in activities where panels[activity.id] == nil {
                    panels[activity.id] = present(activity)
                }
            }
    }

    private static func present(_ activity: DebugSymbolCache.Activity) -> XcodeRunPanel {
        let panel = XcodeRunPanel(title: "Preparing Debugging Symbols")
        panel.host(DebugCacheProgress(run: activity.id))
        panel.present(for: activity.destinationID)
        return panel
    }
}

private struct DebugCacheProgress: View {
    let run: UUID
    @ObservedObject private var cache = VirtualBuddyDebugging.symbolCache

    var body: some View {
        if let activity = cache.activities.first(where: { $0.id == run }) {
            DebugCacheProgressSheet(system: activity.system, detail: activity.detail, fraction: activity.fraction) {
                cache.cancel(run)
            }
        }
    }
}

private struct DebugCacheProgressSheet: View {
    let system: String
    let detail: String
    let fraction: Double?
    let cancel: () -> Void

    var body: some View {
        XcodeRunSheet(title: "Preparing Debugging Symbols",
                      subtitle: "Xcode uses these symbols to show system functions when debugging macOS \(system).") {
            XcodeRunRow(symbol: "shippingbox", title: detail) {
                HStack {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Debugging symbols")
                    if let fraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        } actions: {
            Spacer()
            Button("Cancel", role: .cancel) { cancel() }
                .keyboardShortcut(.cancelAction)
                .airGlassButtonStyle()
        }
    }
}

struct DebugCacheSettings: View {
    let showWhenEmpty: Bool
    @ObservedObject var cache: DebugSymbolCache

    var body: some View {
        if showWhenEmpty || !cache.entries.isEmpty {
            DebugCacheList(entries: cache.entries.map { entry in
                DebugCacheList.Entry(id: entry.id, system: entry.system, bytes: entry.bytes,
                                     inUse: cache.isInUse(entry), removing: cache.isRemoving(entry)) {
                    Task {
                        do { try await cache.remove(entry) }
                        catch { NSApp.presentError(error) }
                    }
                }
            })
        }
    }
}

private struct DebugCacheList: View {
    struct Entry: Identifiable {
        let id: String
        let system: String
        let bytes: Int64
        var inUse = false
        var removing = false
        let remove: () -> Void
    }

    let entries: [Entry]

    var body: some View {
        SettingsDivider()

        SettingsRow("Debugging symbols:") {
            SettingsItemList {
                if entries.isEmpty {
                    Text("No cached guest symbols")
                        .settingsListItemTitle()
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("macOS " + entry.system)
                                    .settingsListItemTitle()
                                Text(entry.bytes.formatted(.byteCount(style: .file)))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(entry.removing ? "Deleting…" : "Delete", action: entry.remove)
                                .disabled(entry.inUse || entry.removing)
                        }
                    }
                }
            }
            SettingsCaption("Xcode uses these symbols to show function names from the VM’s system libraries in stack traces. If you delete them, VirtualBuddy rebuilds the cache the next time you debug that macOS build.")
        }
    }
}

#if DEBUG
#Preview("Copying Symbols") {
    DebugCacheProgressSheet(system: "27.0 (26A100)", detail: "Copying dyld_shared_cache_arm64e.01", fraction: 0.32) {}
}

#Preview("Extracting Symbols") {
    DebugCacheProgressSheet(system: "27.0 (26A100)", detail: "Extracting system libraries (40%)", fraction: 0.82) {}
}

#Preview("Finalizing Symbol Cache") {
    DebugCacheProgressSheet(system: "27.0 (26A100)", detail: "Finalizing symbol cache", fraction: nil) {}
}

#Preview("Cached Symbols") {
    SettingsPane {
        DebugCacheList(entries: [
            .init(id: "26A100", system: "27.0 (26A100)", bytes: 4_300_000_000, inUse: true, remove: {}),
            .init(id: "25B100", system: "26.1 (25B100)", bytes: 3_900_000_000, removing: true, remove: {}),
            .init(id: "25A100", system: "26.0 (25A100)", bytes: 3_800_000_000, remove: {})
        ])
    }
}

#Preview("Empty Symbol Cache") {
    SettingsPane { DebugCacheList(entries: []) }
}
#endif
