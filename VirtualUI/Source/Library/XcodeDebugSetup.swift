import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import VirtualCore

@MainActor
public enum XcodeDebugSetup {
    static func show(for vm: VBVirtualMachine) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["xcodeproj", "xcworkspace"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Choose"
        panel.message = "Choose the Xcode project or workspace containing your macOS app."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let choices = try DebugScheme.choices(in: url)
            guard !choices.isEmpty else { throw Failure("This project has no runnable macOS app schemes or app targets.") }
            let picker = NSPopUpButton()
            let groups = Dictionary(grouping: choices, by: \.name)
            for choice in choices {
                let label = groups[choice.name]?.count == 1 ? choice.name : choice.name + " (" + choice.projectName + ")"
                picker.menu?.addItem(withTitle: label, action: nil, keyEquivalent: "")
            }
            picker.selectItem(at: 0)
            picker.sizeToFit()
            picker.setFrameSize(.init(width: max(260, picker.frame.width), height: picker.frame.height))
            let alert = NSAlert()
            alert.messageText = "Run an app on " + vm.name
            alert.informativeText = "Select the app scheme to build. Log in to the VM with the current VirtualBuddyGuest and Apple’s Command Line Tools or Xcode installed."
            alert.accessoryView = picker
            alert.addButton(withTitle: "Create Scheme")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let key = "IDEDebuggerFeatureSetting" as CFString, domain = "com.apple.dt.Xcode" as CFString
            let current = (CFPreferencesCopyAppValue(key, domain) as? NSNumber)?.intValue ?? 0
            var relaunch = false
            if current & 12 != 12 {
                let consent = NSAlert()
                consent.messageText = "Enable Custom LLDB Commands in Xcode?"
                consent.informativeText = "VirtualBuddy uses this experimental Xcode 27 launch style to connect the built-in debugger to the VM. This changes your Xcode debugger preference and requires relaunching Xcode."
                consent.addButton(withTitle: "Enable")
                consent.addButton(withTitle: "Cancel")
                guard consent.runModal() == .alertFirstButtonReturn else { return }
                CFPreferencesSetAppValue(key, NSNumber(value: current | 12), domain)
                guard CFPreferencesAppSynchronize(domain) else { throw Failure("Could not save the Xcode debugger preference.") }
                relaunch = true
            }
            let file = try choices[picker.indexOfSelectedItem].install(vm: vm.uuid, named: vm.name, app: Bundle.main.bundleURL)
            let done = NSAlert()
            done.messageText = "Xcode scheme created"
            let name = file.deletingPathExtension().lastPathComponent
            done.informativeText = (relaunch ? "Quit and reopen Xcode. " : "") + "Choose “\(name)” and My Mac in the Xcode toolbar, then press ⌘R. The first run caches system symbols for this macOS build."
            done.runModal()
        } catch { NSApp.presentError(error) }
    }

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
