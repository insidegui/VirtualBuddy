import SwiftUI
import VirtualCore

/// Real progress for saving and restoring: it advances as the steps of the operation complete.
struct SavedSessionProgressOverlay: View {
    var title: String
    var phase: SavedSessionPhase

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(.title, design: .rounded, weight: .semibold))

            ProgressView(value: phase.fractionCompleted)
                .frame(width: 240)

            Text(phase.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.smooth, value: phase)
    }
}

/// Shown while the window stays open waiting for the guest to shut down.
struct ShuttingDownOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Shutting Down…")
                .font(.system(.title, design: .rounded, weight: .semibold))

            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 240)

            Text("The window closes once the guest has shut down.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Marks a virtual machine that's saved, with when it was saved.
struct SavedSessionBadge: View {
    var descriptor: VBSavedSessionDescriptor

    var body: some View {
        Label {
            if let date = descriptor.date {
                Text("Saved \(date, format: .dateTime.month().day().hour().minute())")
            } else {
                Text("Saved")
            }
        } icon: {
            Image(systemName: "tray.and.arrow.down.fill")
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}

/// What the user needs to know about a saved session, and how to get rid of it.
struct SavedSessionDetailsSection: View {
    @EnvironmentObject private var controller: VMController
    @EnvironmentObject private var ui: VirtualMachineSessionUI

    var descriptor: VBSavedSessionDescriptor

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("To keep this point for later, duplicate the saved VM before resuming it. Resuming a copy continues that copy.")

                Text("Shared host folders and remote services stay live. Their contents are not preserved or rolled back. A saved session is not a backup, and it may stop working after macOS or VirtualBuddy updates.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Button("Discard Saved Session…", role: .destructive) {
                Task { await ui.discardSavedSessionAfterConfirmation() }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } header: {
            if let date = descriptor.date {
                Text("Saved \(date, format: .dateTime.month().day().year().hour().minute())")
            } else {
                Text("Saved Session")
            }
        }
    }
}

extension VBVirtualMachine {
    /// The screenshot of the saved session, if there's one that can be shown.
    var savedScreenshot: NSImage? {
        guard let descriptor = savedSession, descriptor.isReady, let url = descriptor.screenshotURL else { return nil }
        return NSImage(contentsOf: url)
    }
}
