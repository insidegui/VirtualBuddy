import Foundation

/// Turns what the app answered into what the tool prints.
enum ControlOutput {
    static func json(_ payload: ControlPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data = switch payload {
        case .message(let message): try encoder.encode(["message": message])
        case .machines(let value): try encoder.encode(value)
        case .machine(let value): try encoder.encode(value)
        case .app(let value): try encoder.encode(value)
        case .guest(let value): try encoder.encode(value)
        case .guestInfo(let value): try encoder.encode(value)
        case .appearance(let value): try encoder.encode(value)
        case .tunnels(let value): try encoder.encode(value)
        case .tunnelChange(let value): try encoder.encode(value)
        case .display(let value): try encoder.encode(value)
        case .shares(let value): try encoder.encode(value)
        case .network(let value): try encoder.encode(value)
        case .usb(let value): try encoder.encode(value)
        }

        return String(decoding: data, as: UTF8.self)
    }

    static func json(_ error: ControlError) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(["error": error])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether the payload only confirms that something was done, which `--quiet` leaves out.
    static func isConfirmation(_ payload: ControlPayload) -> Bool {
        switch payload {
        case .message, .tunnelChange: true
        default: false
        }
    }

    static func text(_ payload: ControlPayload) -> String {
        switch payload {
        case .message(let message):
            return message
        case .machines(let machines):
            guard !machines.isEmpty else { return "No virtual machines." }
            return table(["NAME", "STATE", "GUEST APP", "SYSTEM"], machines.map {
                [$0.name, $0.state, $0.guest ?? "-", systemDescription($0)]
            })
        case .machine(let detail):
            return text(detail)
        case .app(let status):
            var lines = fields([
                ("VirtualBuddy", "\(status.version) (\(status.build))"),
                ("Library", status.libraryPath),
                ("Virtual machines", "\(status.machineCount)")
            ])
            if !status.active.isEmpty {
                lines += "\n\n" + table(["RUNNING", "STATE", "GUEST APP"], status.active.map { [$0.name, $0.state, $0.guest ?? "-"] })
            }
            return lines
        case .guest(let guest):
            return guest.appVersion.map { "\(guest.status) (VirtualBuddyGuest \($0))" } ?? guest.status
        case .guestInfo(let info):
            return text(info)
        case .appearance(let appearance):
            let mode = appearance.darkMode.map { $0 ? "dark" : "light" } ?? "unknown"
            return appearance.followsHost ? "\(mode) (follows this Mac)" : mode
        case .tunnels(let tunnels):
            return text(tunnels)
        case .tunnelChange(let change):
            let tunnel = "\(change.tunnel.listen) → \(change.tunnel.destination)"
            switch change.outcome {
            case "added": return "Added tunnel \(tunnel)."
            case "awaiting-review": return "Tunnel \(tunnel) is waiting to be reviewed in VirtualBuddy."
            case "enabled": return "Turned on tunnel \(tunnel)."
            case "disabled": return "Turned off tunnel \(tunnel)."
            case "removed": return "Removed tunnel \(tunnel)."
            case "declined": return "Declined tunnel \(tunnel)."
            default: return "\(change.outcome): \(tunnel)"
            }
        case .display(let display):
            return text(display)
        case .shares(let shares):
            guard !shares.isEmpty else { return "No shared folders." }
            return table(["PATH", "NAME IN GUEST", "ACCESS", "STATE"], shares.map {
                [$0.path, $0.name, $0.readOnly ? "read-only" : "read-write", $0.enabled ? "on" : "off"]
            })
        case .network(let network):
            var sections = [String]()
            if network.devices.isEmpty {
                sections.append("No network devices.")
            } else {
                sections.append(table(["DEVICE", "KIND", "MAC ADDRESS"], network.devices.map { [$0.name, $0.kind, $0.macAddress] }))
            }
            if !network.bridgeInterfaces.isEmpty {
                sections.append(table(["INTERFACE", "NAME", "BRIDGED"], network.bridgeInterfaces.map { [$0.id, $0.name, $0.active ? "yes" : "-"] }))
            }
            return sections.joined(separator: "\n\n")
        case .usb(let devices):
            guard !devices.isEmpty else { return "No USB devices." }
            return table(["ID", "NAME", "VENDOR:PRODUCT", "STATE"], devices.map {
                [$0.id, $0.name, "\($0.vendorID):\($0.productID)", $0.error ?? ($0.attached ? "attached" : "-")]
            })
        }
    }

    private static func systemDescription(_ machine: ControlMachine) -> String {
        let system = machine.system == "mac" ? "macOS" : "Linux"
        return machine.osVersion.map { "\(system) \($0)" } ?? system
    }

    private static func text(_ detail: ControlMachineDetail) -> String {
        let machine = detail.machine
        var rows: [(String, String)] = [
            ("Name", machine.name),
            ("State", machine.detail.map { "\(machine.state) (\($0))" } ?? machine.state),
            ("System", systemDescription(machine)),
            ("Guest app", machine.guest ?? "-"),
            ("UUID", machine.uuid.uuidString),
            ("Path", machine.path)
        ]
        if let display = detail.display { rows.append(("Display", text(display))) }
        if let appearance = detail.appearance { rows.append(("Appearance", text(.appearance(appearance)))) }
        if detail.tunnelCount > 0 || detail.pendingTunnelCount > 0 {
            let pending = detail.pendingTunnelCount > 0 ? ", \(detail.pendingTunnelCount) waiting for review" : ""
            rows.append(("Tunnels", "\(detail.tunnelCount)\(pending)"))
        }
        return fields(rows)
    }

    private static func text(_ info: ControlGuestInfo) -> String {
        var rows: [(String, String)] = [("System", [info.osVersion, info.osBuild.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))]
        if let value = info.computerName { rows.append(("Computer name", value)) }
        if let value = info.architecture { rows.append(("Architecture", value)) }
        if let value = info.processorCount { rows.append(("Processors", "\(value)")) }
        if let value = info.memoryBytes { rows.append(("Memory", ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory))) }
        if let value = info.kernelVersion { rows.append(("Kernel", value)) }
        if let value = info.bootDate { rows.append(("Started", value.formatted(date: .abbreviated, time: .shortened))) }
        if let value = info.guestAppVersion {
            rows.append(("VirtualBuddyGuest", info.guestAppBuild.map { "\(value) (\($0))" } ?? value))
        }
        if let value = info.systemIntegrityProtection { rows.append(("System Integrity Protection", value)) }
        rows.append(("Reported", info.reportedAt.formatted(date: .abbreviated, time: .shortened)))
        return fields(rows)
    }

    private static func text(_ tunnels: ControlTunnels) -> String {
        func rows(_ list: [ControlTunnel]) -> [[String]] {
            list.map { [String($0.id.uuidString.prefix(8)).lowercased(), $0.listen, $0.destination, $0.enabled ? "on" : "off", $0.status ?? "-"] }
        }

        var sections = [String]()
        if tunnels.tunnels.isEmpty {
            sections.append(tunnels.review == "unavailable" ? "The service tunnels can't be read." : "No service tunnels.")
        } else {
            sections.append(table(["ID", "LISTENS ON", "CONNECTS TO", "STATE", "STATUS"], rows(tunnels.tunnels)))
        }
        if let detail = tunnels.detail { sections.append(detail) }
        if !tunnels.pending.isEmpty {
            sections.append("Waiting for review in VirtualBuddy:\n" + table(["ID", "LISTENS ON", "CONNECTS TO"], rows(tunnels.pending).map { Array($0.prefix(3)) }))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func text(_ display: ControlDisplay) -> String {
        "\(display.width)x\(display.height) at \(display.pixelsPerInch) ppi, automatic resizing \(display.automaticallyResizes ? "on" : "off")"
    }

    static func fields(_ rows: [(String, String)]) -> String {
        let width = rows.map(\.0.count).max() ?? 0
        return rows
            .map { "\(($0.0 + ":").padding(toLength: width + 1, withPad: " ", startingAt: 0)) \($0.1)" }
            .joined(separator: "\n")
    }

    /// Columns are padded to the widest cell, except for the last one, so that lines don't end in spaces.
    static func table(_ header: [String], _ rows: [[String]]) -> String {
        let all = [header] + rows
        let widths = header.indices.map { column in all.map { $0[column].count }.max() ?? 0 }
        return all.map { row in
            row.enumerated().map { column, cell in
                column == row.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }
}
