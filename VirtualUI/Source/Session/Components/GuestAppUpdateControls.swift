import SwiftUI
import VirtualWormhole
import UniformTypeIdentifiers

struct GuestAppUpdateControls: View {
    var state: GuestAppUpdateState?
    var update: () -> Void
    var exportInstaller: (URL) async throws -> Void

    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exported = false
    @State private var exportTask: Task<Void, Never>?

    private var incompatible: Bool {
        state?.osVersion != nil && state?.target != nil && state?.isCompatible == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state?.updateAvailable == true ? "VirtualBuddyGuest Update Available" : "Guest App Updates")
                .font(.subheadline.weight(.medium))

            if let state, state.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progressText(state.phase))
                }
                Text("Only the guest app restarts. Your virtual machine keeps running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if incompatible, let target = state?.target {
                Text("The current installer requires macOS \(target.minimumOS) or later. This guest needs a compatible legacy version of VirtualBuddyGuest.")
                    .foregroundStyle(.secondary)
            } else if state?.updateAvailable == true, let target = state?.target {
                Text("VirtualBuddyGuest \(target.version) (build \(target.build.formatted(.number.grouping(.never)))) is available.")
                if state?.supportsRemoteUpdate == true {
                    Button("Update VirtualBuddyGuest", action: update)
                        .disabled(state?.canUpdate != true)
                } else {
                    Text("This guest app needs a one-time manual update. Export the installer to a shared folder, then open it inside the virtual machine and launch VirtualBuddyGuest.")
                        .foregroundStyle(.secondary)
                }
            } else if state?.phase == .succeeded {
                Text("VirtualBuddyGuest was updated successfully.")
            } else if state?.target != nil && (state?.installed != nil || state?.reportedBuild != nil) {
                Text("VirtualBuddyGuest is up to date.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Update status is unavailable. You can install the guest app manually using an exported installer.")
                    .foregroundStyle(.secondary)
            }

            if let error = state?.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Button(isExporting ? "Exporting Installer…" : "Export Guest Installer…") {
                export()
            }
            .disabled(isExporting || state?.isBusy == true || incompatible)

            if exported {
                Text("Open the exported disk image inside the virtual machine, then double-click VirtualBuddyGuest to install it.")
                    .font(.caption)
            }

            if state?.supportsRemoteUpdate != true && state?.isBusy != true {
                Text("Without a shared folder, shut down the guest completely and start it again in VirtualBuddy to attach the current installer. Saving and resuming keeps the old installer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let exportError {
                Text(exportError).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear {
            exportTask?.cancel()
            exportTask = nil
        }
    }

    private func progressText(_ phase: GuestAppUpdateState.Phase) -> LocalizedStringKey {
        switch phase {
        case .preparing: "Preparing update…"
        case .transferring: "Sending update to guest…"
        case .installing: "Validating and staging update…"
        case .reconnecting: "Waiting for updated guest app…"
        default: "Updating VirtualBuddyGuest…"
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.diskImage]
        panel.nameFieldStringValue = "VirtualBuddyGuest-Update.dmg"
        panel.message = "Choose a shared folder that you can open inside the virtual machine."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportTask = Task {
            isExporting = true
            exportError = nil
            exported = false
            defer { isExporting = false; exportTask = nil }
            do {
                try await exportInstaller(url)
                exported = true
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch is CancellationError {
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}
