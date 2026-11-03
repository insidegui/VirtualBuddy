import SwiftUI
import VirtualCore
import VirtualWormhole

struct VMInfoView: View {
    @EnvironmentObject private var library: VMLibraryController
    let initialMachine: VBVirtualMachine

    private var machine: VBVirtualMachine {
        library.virtualMachines.first { $0.uuid == initialMachine.uuid } ?? initialMachine
    }

    var body: some View {
        VMInfoContent(name: machine.name, bundleURL: machine.bundleURL,
                      systemType: machine.configuration.systemType, report: machine.guestSystemInformation)
    }
}

private struct VMInfoContent: View {
    let name: String
    let bundleURL: URL
    let systemType: VBGuestType
    let report: VBGuestSystemInformation?

    var body: some View {
        Form {
            Section {
                LabeledContent { Text(name) } label: { Text("Name", bundle: #bundle) }
                LabeledContent { Text(bundleURL.path).lineLimit(3) } label: { Text("Location", bundle: #bundle) }
            }
            if let report {
                GuestSystemInfoSection(information: report.information)
                Section {
                    LabeledContent {
                        Text(report.receivedAt, format: .dateTime.year().month().day().hour().minute().second())
                    } label: {
                        Text("Last Reported", bundle: #bundle)
                    }
                    Text("Information reflects the guest when it last reported to VirtualBuddy. It remains available while the VM is off and may differ from its current configuration.", bundle: #bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("No Guest Information", bundle: #bundle).font(.headline)
                    if systemType == .mac {
                        Text("Start this VM and run an up-to-date VirtualBuddy Guest app with guest integration enabled to collect system information.", bundle: #bundle)
                    } else {
                        Text("Guest system information is available for macOS VMs running VirtualBuddy Guest.", bundle: #bundle)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
        .frame(minWidth: 440, idealWidth: 500, maxWidth: .infinity, minHeight: 400, idealHeight: 680, maxHeight: .infinity)
        .windowTitle(String(localized: "\(name) Info", bundle: #bundle))
        .windowStyleMask([.titled, .closable, .resizable])
    }
}

private struct GuestSystemInfoSection: View {
    let information: GuestSystemInformation

    var body: some View {
        Section {
            LabeledContent { Text("macOS \(information.osVersion)", bundle: #bundle) } label: { Text("Operating System", bundle: #bundle) }
            InfoValueRow(title: "Build", value: information.osBuild)
            InfoValueRow(title: "Kernel", value: information.kernelVersion)
            LabeledContent { SIPStatusText(status: information.sipStatus) } label: { Text("System Integrity Protection", bundle: #bundle) }
            if let details = information.sipDescription {
                DisclosureGroup {
                    Text(details).font(.system(.caption, design: .monospaced))
                } label: {
                    Text("SIP Details", bundle: #bundle)
                }
            }
        } header: { Text("System", bundle: #bundle) }

        Section {
            InfoValueRow(title: "Computer Name", value: information.computerName)
            InfoValueRow(title: "Architecture", value: information.architecture)
            if let count = information.processorCount {
                LabeledContent { Text(count, format: .number) } label: { Text("Processors", bundle: #bundle) }
            }
            if let bytes = information.memoryBytes, let count = Int64(exactly: bytes) {
                LabeledContent {
                    Text(count, format: .byteCount(style: .memory))
                } label: { Text("Memory", bundle: #bundle) }
            }
            if let date = information.bootDate {
                LabeledContent {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                } label: { Text("Last Startup", bundle: #bundle) }
            }
            InfoValueRow(title: "Guest App Version", value: information.guestAppVersion)
            InfoValueRow(title: "Guest App Build", value: information.guestAppBuild)
        } header: { Text("Guest", bundle: #bundle) }
    }
}

private struct InfoValueRow: View {
    let title: LocalizedStringKey
    let value: String?

    var body: some View {
        LabeledContent {
            if let value { Text(value) } else { Text("Unknown", bundle: #bundle).foregroundStyle(.secondary) }
        } label: {
            Text(title, bundle: #bundle)
        }
    }
}

struct SIPStatusText: View {
    let status: GuestSystemInformation.SIPStatus

    var body: some View {
        switch status {
        case .enabled: Text("Enabled", bundle: #bundle)
        case .disabled: Text("Disabled", bundle: #bundle)
        case .custom: Text("Custom Configuration", bundle: #bundle)
        case .unknown: Text("Unknown", bundle: #bundle)
        }
    }
}

struct GuestSystemInfoSummary: View {
    let report: VBGuestSystemInformation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("macOS \(report.information.osVersion)", bundle: #bundle)
            HStack(spacing: 6) {
                if let build = report.information.osBuild { Text(build) }
                Label {
                    HStack(spacing: 3) {
                        Text("SIP", bundle: #bundle)
                        SIPStatusText(status: report.information.sipStatus)
                    }
                } icon: { Image(systemName: "lock.shield") }
            }
            .font(.caption2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(Text("Last reported \(report.receivedAt, format: .dateTime.year().month().day().hour().minute())", bundle: #bundle))
    }
}

#if DEBUG
#Preview("Get Info") {
    let information = GuestSystemInformation(
        osVersion: "26.1.0", osBuild: "25B78", kernelVersion: "25.1.0", computerName: "Development VM",
        architecture: "arm64", processorCount: 4, memoryBytes: 8_589_934_592,
        bootDate: Date.now.addingTimeInterval(-3600), guestAppVersion: "2.2", guestAppBuild: "200",
        sipDescription: "System Integrity Protection status: enabled."
    )
    let report = VBGuestSystemInformation(receivedAt: .now, information: information)
    VMInfoContent(name: "macOS Development", bundleURL: URL(fileURLWithPath: "/Users/developer/VirtualBuddy/macOS Development.vbvm"),
                  systemType: .mac, report: report)
    .frame(width: 500, height: 680)
}

#Preview("No Guest Information") {
    VMInfoContent(name: "New VM", bundleURL: URL(fileURLWithPath: "/Users/developer/VirtualBuddy/New VM.vbvm"),
                  systemType: .mac, report: nil)
    .frame(width: 500, height: 400)
}
#endif
