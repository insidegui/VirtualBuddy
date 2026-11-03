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
            }
            if let report {
                GuestSystemInfoSection(information: report.information)

                Section {
                    LabeledContent {
                        Text(report.receivedAt, format: .dateTime.year().month().day().hour().minute().second())
                    } label: {
                        Text("Last Reported", bundle: #bundle)
                    }
                } footer: {
                    Text("Information reflects the guest when it last reported to VirtualBuddy. It remains available while the VM is off and may differ from its current configuration.", bundle: #bundle)
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
        .frame(minWidth: 440, idealWidth: 500, maxWidth: .infinity, minHeight: 400, idealHeight: 700, maxHeight: .infinity)
        .windowTitle(String(localized: "\(name) Info", bundle: #bundle))
        .windowStyleMask([.titled, .closable, .resizable])
    }
}

private struct GuestSystemInfoSection: View {
    let information: GuestSystemInformation

    @State private var showingSIPDetails = false

    var body: some View {
        Section {
            LabeledContent { Text("macOS \(information.osVersion)", bundle: #bundle) } label: { Text("Operating System", bundle: #bundle) }

            InfoValueRow(title: "Build", value: information.osBuild)

            InfoValueRow(title: "Kernel", value: information.kernelVersion)

            LabeledContent {
                HStack {
                    SIPStatusText(status: information.sipStatus)

                    if let details = information.sipDescription {
                        Button {
                            showingSIPDetails.toggle()
                        } label: {
                            Image(systemName: "info")
                                .symbolVariant(.circle)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showingSIPDetails) {
                            SIPDetailsView(details)
                        }
                    }
                }
            } label: {
                Text("System Integrity Protection", bundle: #bundle)
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

struct SIPDetailsView: View {
    let details: String

    init(_ details: String) {
        self.details = details
    }

    var body: some View {
        ScrollView(.vertical) {
            Text(details)
                .font(.system(.caption).monospaced())
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(16, for: .scrollContent)
        .frame(maxWidth: 340, maxHeight: 320)
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

#if DEBUG
#Preview("Get Info") {
    let information = GuestSystemInformation(
        osVersion: "26.1.0", osBuild: "25B78", kernelVersion: "25.1.0", computerName: "Development VM",
        architecture: "arm64", processorCount: 4, memoryBytes: 8_589_934_592,
        bootDate: Date.now.addingTimeInterval(-3600), guestAppVersion: "2.2", guestAppBuild: "200",
        sipDescription: "System Integrity Protection status: enabled."
    )
    let report = VBGuestSystemInformation(receivedAt: .now, information: information)
    VMInfoContent(name: "macOS Development", bundleURL: URL(fileURLWithPath: "/Users/johndoe/Library/Application Support/VirtualBuddy/New VM.vbvm"),
                  systemType: .mac, report: report)
    .frame(width: 500, height: 680)
}

#Preview("No Guest Information") {
    VMInfoContent(name: "New VM", bundleURL: URL(fileURLWithPath: "/Users/johndoe/Library/Application Support/VirtualBuddy/New VM.vbvm"),
                  systemType: .mac, report: nil)
    .frame(width: 500, height: 400)
}
#endif
