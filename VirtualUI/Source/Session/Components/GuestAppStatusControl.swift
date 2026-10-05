import SwiftUI
import VirtualCore
import ManagedPreferencesUI

/// Toolbar indicator for the status of the VirtualBuddyGuest app in a running virtual machine.
struct GuestAppStatusControl: View {
    var status: GuestAppConnectionStatus

    @State private var isShowingDetail = false

    var body: some View {
        Button {
            isShowingDetail.toggle()
        } label: {
            Label {
                Text(status.title)
            } icon: {
                Image(.guestSymbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .opacity(status == .connected ? 1 : 0.6)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(status.indicatorColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: 2)
                    }
            }
            .labelStyle(.iconOnly)
        }
        .help(status.title)
        .popover(isPresented: $isShowingDetail, arrowEdge: .bottom) {
            GuestAppStatusDetail(status: status)
        }
    }
}

private struct GuestAppStatusDetail: View {
    var status: GuestAppConnectionStatus

    @ManagedValue(for: .disableGuestApp, schema: VirtualBuddyManagedPreferences.schema, default: false)
    private var guestAppMountingDisabled: Bool

    private var showsInstallTutorial: Bool { status == .disconnected || status == .unknown }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(status.indicatorColor)
                    .frame(width: 8, height: 8)

                Text(status.title)
                    .font(.headline)
            }

            Text(status.explanation)
                .foregroundStyle(.secondary)

            if showsInstallTutorial {
                Divider()

                if guestAppMountingDisabled {
                    ManagedRestrictionBannerView(title: "Guest app mounting is disabled by your organization.")
                } else {
                    installTutorial
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300, alignment: .leading)
        .padding()
    }

    private static let installSteps = [
        "Open a Finder window in the virtual machine.",
        "Select the “Guest” disk in the Finder sidebar.",
        "Double-click the VirtualBuddyGuest app icon."
    ]

    @ViewBuilder
    private var installTutorial: some View {
        Text("Install VirtualBuddyGuest")
            .font(.subheadline.weight(.medium))

        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.installSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Text(step)
                }
            }
        }

        if status == .disconnected {
            Text("If VirtualBuddyGuest is already installed, make sure it’s running in the virtual machine.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension GuestAppConnectionStatus {
    var title: String {
        switch self {
        case .disabled: "VirtualBuddyGuest Is Disabled"
        case .unknown: "VirtualBuddyGuest"
        case .disconnected: "VirtualBuddyGuest Is Not Connected"
        case .connected: "VirtualBuddyGuest Is Connected"
        }
    }

    var explanation: String {
        switch self {
        case .disabled:
            "VirtualBuddyGuest is turned off for this virtual machine. To use it, shut down the virtual machine, then turn on “Enable VirtualBuddyGuest App” in the Guest App settings."
        case .unknown:
            "This virtual machine uses a legacy version of VirtualBuddyGuest. It mounts shared folders automatically, but can’t report its status to VirtualBuddy."
        case .disconnected:
            "With VirtualBuddyGuest running in the virtual machine, shared folders are mounted automatically and the clipboard can be shared with your Mac."
        case .connected:
            "Shared folders are mounted automatically and the clipboard can be shared between your Mac and the virtual machine."
        }
    }

    var indicatorColor: Color {
        switch self {
        case .disabled, .unknown: .gray
        case .disconnected: .orange
        case .connected: .green
        }
    }
}

#if DEBUG
#Preview("Connected") {
    GuestAppStatusDetail(status: .connected)
}

#Preview("Not Connected") {
    GuestAppStatusDetail(status: .disconnected)
}

#Preview("Legacy") {
    GuestAppStatusDetail(status: .unknown)
}

#Preview("Disabled") {
    GuestAppStatusDetail(status: .disabled)
}

#Preview("Toolbar Control") {
    HStack {
        GuestAppStatusControl(status: .connected)
        GuestAppStatusControl(status: .disconnected)
        GuestAppStatusControl(status: .unknown)
        GuestAppStatusControl(status: .disabled)
    }
    .padding()
}
#endif
