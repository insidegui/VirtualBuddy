import AppKit
import SwiftUI
import Combine
import VirtualCore
import MacDebugHost

@MainActor
public enum XcodeDebugSetup {
    private static var observer: AnyCancellable?
    private static var panels: [UUID: NSPanel] = [:]

    public static func observeCachePreparation() {
        observer = VirtualBuddyDebugging.symbolCache.$activities
            .removeDuplicates { $0.map(\.id) == $1.map(\.id) }
            .receive(on: RunLoop.main)
            .sink { activities in
                let active = Set(activities.map(\.id))
                for (id, panel) in panels where !active.contains(id) {
                    panel.parent?.removeChildWindow(panel)
                    panel.close()
                    panels[id] = nil
                }
                for activity in activities where panels[activity.id] == nil {
                    panels[activity.id] = present(activity)
                }
            }
    }

    private static func present(_ activity: DebugSymbolCache.Activity) -> NSPanel {
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 420, height: 150), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Preparing Xcode Debugging Symbols"
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.contentView = NSHostingView(rootView: DebugCacheProgress(run: activity.id))

        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
        if let session = VirtualMachineSessionUIManager.shared.sessions.values.first(where: { $0.virtualMachine.uuid == activity.destinationID }),
           let window = session.hostWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            session.bringToFront()
            var frame = panel.frame
            frame.origin = CGPoint(x: window.frame.midX - frame.width / 2, y: window.frame.midY - frame.height / 2)
            panel.setFrame(panel.constrainFrameRect(frame, to: window.screen), display: false)
            window.addChildWindow(panel, ordered: .above)
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        return panel
    }
}

private struct DebugCacheProgress: View {
    let run: UUID
    @ObservedObject private var cache = VirtualBuddyDebugging.symbolCache
    var body: some View {
        if let activity = cache.activities.first(where: { $0.id == run }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("macOS " + activity.system).font(.headline)
                ProgressView(value: activity.fraction) { Text(activity.detail) }
                    .progressViewStyle(.linear)
                Button("Cancel") { cache.cancel(activity.id) }
            }
            .padding()
            .frame(minWidth: 400)
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
