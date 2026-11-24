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
            XcodeRunSheet(title: "Preparing Debugging Symbols",
                          subtitle: "Xcode uses these symbols to show system functions when debugging macOS \(activity.system).") {
                XcodeRunRow(symbol: "shippingbox", title: activity.detail) {
                    HStack {
                        ProgressView(value: activity.fraction)
                            .progressViewStyle(.linear)
                            .accessibilityLabel("Debugging symbols")
                        if let fraction = activity.fraction {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            } actions: {
                Spacer()
                Button("Cancel", role: .cancel) { cache.cancel(run) }
                    .keyboardShortcut(.cancelAction)
                    .airGlassButtonStyle()
            }
        }
    }
}

struct DebugCacheSettings: View {
    let showWhenEmpty: Bool
    @ObservedObject private var cache = VirtualBuddyDebugging.symbolCache

    var body: some View {
        if showWhenEmpty || !cache.entries.isEmpty {
            SettingsDivider()

            SettingsRow("Debugging symbols:") {
                SettingsItemList {
                    if cache.entries.isEmpty {
                        Text("No cached guest symbols")
                            .settingsListItemTitle()
                    } else {
                        ForEach(cache.entries) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("macOS " + entry.system)
                                        .settingsListItemTitle()
                                    Text(entry.bytes.formatted(.byteCount(style: .file)))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(cache.isRemoving(entry) ? "Deleting…" : "Delete") {
                                    Task {
                                        do {
                                            try await cache.remove(entry)
                                        } catch {
                                            NSApp.presentError(error)
                                        }
                                    }
                                }
                                .disabled(cache.isInUse(entry) || cache.isRemoving(entry))
                            }
                        }
                    }
                }
                SettingsCaption("Xcode uses these symbols to show function names from the VM’s system libraries in stack traces. If you delete them, VirtualBuddy rebuilds the cache the next time you debug that macOS build.")
            }
        }
    }
}
