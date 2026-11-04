import SwiftUI
import VirtualWormhole
import VirtualCore

struct GuestAppUpdateControls: View {
    var state: GuestAppUpdateState?
    var update: () -> Void
    var installerExport: GuestInstallerExport?
    var exportInstaller: () -> Void

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

            Button(installerExport?.phase == .exporting ? "Exporting Installer…" : "Export Guest Installer…", action: exportInstaller)
                .disabled(installerExport?.isBusy == true || state?.isBusy == true || incompatible)

            if installerExport?.exportedURL != nil {
                Text("Open the exported disk image inside the virtual machine, then double-click VirtualBuddyGuest to install it.")
                    .font(.caption)
            }

            if state?.supportsRemoteUpdate != true && state?.isBusy != true {
                Text("Without a shared folder, shut down the guest completely and start it again in VirtualBuddy to attach the current installer. Saving and resuming keeps the old installer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let exportError = installerExport?.errorMessage {
                Text(exportError).font(.caption).foregroundStyle(.red)
            }
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

}
