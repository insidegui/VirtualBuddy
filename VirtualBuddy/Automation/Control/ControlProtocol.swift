import Foundation
import VirtualWormhole

/// What `vbctl` and the app say to each other over the control socket.
///
/// Both ends are the same executable, so the types below only have to agree with themselves. The version is there
/// for the one case where they don't: a tool from an updated app talking to a copy of the app that's still running.
enum ControlProtocol {
    static let version = 1

    /// The socket's folder is in `/tmp` because Darwin limits the length of Unix-domain socket addresses.
    static var runtimeDirectory: URL { URL(fileURLWithPath: "/private/tmp/vbctl-\(getuid())") }

    /// Named after the app's bundle identifier, so that differently signed builds of the app don't answer each other's tools.
    static var socketURL: URL {
        runtimeDirectory.appendingPathComponent((Bundle.main.bundleIdentifier ?? "codes.rambo.VirtualBuddy") + ".sock")
    }
}

struct ControlRequest: Codable, Sendable {
    var version = ControlProtocol.version
    var command: ControlCommand
    /// How long the app waits for what the command is waiting for, in seconds. Without one it waits until the tool goes away.
    var timeout: Double?
}

enum ControlCommand: Codable, Sendable {
    case list(runningOnly: Bool)
    case status(vm: String?)
    case library

    case open(vm: String)
    case start(vm: String, options: ControlStartOptions)
    case stop(vm: String, force: Bool, wait: Bool)
    case pause(vm: String)
    case resume(vm: String)
    case save(vm: String)

    case guestStatus(vm: String, wait: Bool)
    case guestInfo(vm: String)
    case guestAppearance(vm: String, change: ControlAppearanceChange?)

    case tunnelList(vm: String)
    case tunnelAdd(vm: String, listen: TunnelSide, destination: TunnelSide, wait: Bool)
    case tunnelSetEnabled(vm: String, tunnel: String, enabled: Bool)
    case tunnelRemove(vm: String, tunnel: String)
    case tunnelDecline(vm: String, request: String)

    case display(vm: String, change: ControlDisplayChange)

    case shareList(vm: String)
    case shareAdd(vm: String, path: String, readOnly: Bool)
    case shareRemove(vm: String, path: String)

    case networkStatus(vm: String)
    case networkReconnect(vm: String)
    case networkBridge(vm: String, interface: String)

    case usbList(vm: String)
    case usbSetAttached(vm: String, device: String, attached: Bool)
}

struct ControlStartOptions: Codable, Sendable {
    var recovery = false
    var dfu = false
    var installDevice = false
    var discardSavedState = false
    var waitForGuest = false
}

enum ControlAppearanceChange: String, Codable, Sendable, CaseIterable {
    case dark, light, toggle
    /// Follows the host's appearance.
    case auto
}

struct ControlDisplayChange: Codable, Sendable {
    var width: Int?
    var height: Int?
    var pixelsPerInch: Int?
    var automaticallyResizes: Bool?

    var isEmpty: Bool { width == nil && height == nil && pixelsPerInch == nil && automaticallyResizes == nil }
}

enum ControlReply: Codable, Sendable {
    /// Progress while a command waits. Any number of these come before the result.
    case event(String)
    case success(ControlPayload)
    case failure(ControlError)
}

struct ControlError: LocalizedError, Codable, Sendable, Equatable {
    /// Stable identifiers: scripts see them in `--json` output, and each one maps to an exit code.
    enum Code: String, Codable, Sendable, CaseIterable {
        case failure
        case accessDisabled
        case unreachable
        case incompatibleVersion
        case notFound
        case ambiguous
        case invalidState
        case guestUnavailable
        case unsupported
        case timedOut
        case reviewRequired
        case restrictedByOrganization
    }

    var code: Code
    var message: String

    init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    var errorDescription: String? { message }

    var exitCode: Int32 {
        switch code {
        case .failure: 1
        case .accessDisabled, .unreachable, .incompatibleVersion: 3
        case .notFound, .ambiguous: 4
        case .invalidState: 5
        case .guestUnavailable, .unsupported: 6
        case .timedOut: 7
        case .reviewRequired, .restrictedByOrganization: 8
        }
    }
}

enum ControlPayload: Codable, Sendable {
    case message(String)
    case machines([ControlMachine])
    case machine(ControlMachineDetail)
    case app(ControlAppStatus)
    case guest(ControlGuestStatus)
    case guestInfo(ControlGuestInfo)
    case appearance(ControlAppearance)
    case tunnels(ControlTunnels)
    case tunnelChange(ControlTunnelChange)
    case display(ControlDisplay)
    case shares([ControlShare])
    case network(ControlNetwork)
    case usb([ControlUSBDevice])
}

struct ControlMachine: Codable, Sendable {
    var name: String
    var uuid: UUID
    var path: String
    var system: String
    var state: String
    /// What the state is in the middle of, such as the step of a save.
    var detail: String?
    /// `nil` when the guest can't run the guest app.
    var guest: String?
    var osVersion: String?
}

struct ControlMachineDetail: Codable, Sendable {
    var machine: ControlMachine
    var guestInfo: ControlGuestInfo?
    var appearance: ControlAppearance?
    var display: ControlDisplay?
    var tunnelCount: Int
    var pendingTunnelCount: Int
}

struct ControlAppStatus: Codable, Sendable {
    var version: String
    var build: String
    var libraryPath: String
    var machineCount: Int
    var active: [ControlMachine]
}

struct ControlGuestStatus: Codable, Sendable {
    var status: String
    var appVersion: String?
}

struct ControlGuestInfo: Codable, Sendable {
    /// When the guest last reported this, by the host's clock.
    var reportedAt: Date
    var osVersion: String
    var osBuild: String?
    var kernelVersion: String?
    var computerName: String?
    var architecture: String?
    var processorCount: Int?
    var memoryBytes: UInt64?
    var bootDate: Date?
    var guestAppVersion: String?
    var guestAppBuild: String?
    var systemIntegrityProtection: String?
}

struct ControlAppearance: Codable, Sendable {
    /// `nil` until a connected guest reports its appearance.
    var darkMode: Bool?
    var followsHost: Bool
    /// Set when a change also turned off following the host.
    var note: String?
}

struct ControlTunnel: Codable, Sendable {
    var id: UUID
    var listen: String
    var destination: String
    var enabled: Bool
    var status: String?
}

struct ControlTunnels: Codable, Sendable {
    /// `approved`, `needs-review`, `none` or `unavailable`.
    var review: String
    var detail: String?
    var tunnels: [ControlTunnel]
    /// Tunnels waiting for the user to review them in the app.
    var pending: [ControlTunnel]
}

struct ControlTunnelChange: Codable, Sendable {
    /// `added`, `awaiting-review`, `enabled`, `disabled`, `removed` or `declined`.
    var outcome: String
    var tunnel: ControlTunnel
}

struct ControlDisplay: Codable, Sendable {
    var width: Int
    var height: Int
    var pixelsPerInch: Int
    var automaticallyResizes: Bool
}

struct ControlShare: Codable, Sendable {
    var path: String
    var name: String
    var readOnly: Bool
    var enabled: Bool
}

struct ControlNetwork: Codable, Sendable {
    struct Device: Codable, Sendable {
        var name: String
        var kind: String
        var macAddress: String
    }

    struct Interface: Codable, Sendable {
        var id: String
        var name: String
        var active: Bool
    }

    var devices: [Device]
    /// Host interfaces that a bridged device can use.
    var bridgeInterfaces: [Interface]
    var canChangeBridgeInterface: Bool
}

struct ControlUSBDevice: Codable, Sendable {
    var id: String
    var name: String
    var vendorID: String
    var productID: String
    var attached: Bool
    var error: String?
}

// MARK: - Tunnel Endpoints

/// One end of a service tunnel as it's written on the command line: `host:8080`, `guest:tcp6:8080` or `host:/tmp/service.sock`.
struct TunnelSide: Codable, Sendable, Equatable, CustomStringConvertible {
    var onHost: Bool
    var endpoint: TunnelEndpoint

    init(onHost: Bool, endpoint: TunnelEndpoint) {
        self.onHost = onHost
        self.endpoint = endpoint
    }

    init?(_ text: String) {
        guard let separator = text.firstIndex(of: ":") else { return nil }
        switch text[..<separator].lowercased() {
        case "host": onHost = true
        case "guest": onHost = false
        default: return nil
        }

        let address = String(text[text.index(after: separator)...])
        let endpoint: TunnelEndpoint
        if address.hasPrefix("/") {
            endpoint = .unix(address)
        } else if address.lowercased().hasPrefix("tcp6:"), let port = UInt16(address.dropFirst(5)) {
            endpoint = .tcp6(port)
        } else if address.lowercased().hasPrefix("tcp:"), let port = UInt16(address.dropFirst(4)) {
            endpoint = .tcp(port)
        } else if let port = UInt16(address) {
            endpoint = .tcp(port)
        } else {
            return nil
        }

        guard endpoint.isValid else { return nil }
        self.endpoint = endpoint
    }

    var description: String {
        let side = onHost ? "host" : "guest"
        switch endpoint {
        case .tcp(let port): return "\(side):\(port)"
        case .tcp6(let port): return "\(side):tcp6:\(port)"
        case .unix(let path): return "\(side):\(path)"
        }
    }
}

extension ServiceTunnel {
    /// A tunnel always connects the two sides, so its ends have to be on different ones.
    init?(listen: TunnelSide, destination: TunnelSide) {
        guard listen.onHost != destination.onHost else { return nil }
        self.init(listensOnHost: listen.onHost, listener: listen.endpoint, destination: destination.endpoint)
    }

    var listenSide: TunnelSide { TunnelSide(onHost: listensOnHost, endpoint: listener) }
    var destinationSide: TunnelSide { TunnelSide(onHost: !listensOnHost, endpoint: destination) }

    /// Finds the tunnel a command-line argument refers to: the start of its identifier, or the end it listens on.
    static func resolve(_ reference: String, in tunnels: [ServiceTunnel]) throws -> ServiceTunnel {
        let matches: [ServiceTunnel]
        if let side = TunnelSide(reference) {
            matches = tunnels.filter { $0.listenSide == side }
        } else {
            let prefix = reference.uppercased()
            guard prefix.count >= 4 else {
                throw ControlError(.notFound, "\"\(reference)\" isn't a tunnel. Use the end it listens on, such as host:8080, or at least four characters of its identifier.")
            }
            matches = tunnels.filter { $0.id.uuidString.hasPrefix(prefix) }
        }
        guard let match = matches.first else { throw ControlError(.notFound, "There's no service tunnel matching \"\(reference)\".") }
        guard matches.count == 1 else { throw ControlError(.ambiguous, "More than one service tunnel matches \"\(reference)\". Use more of its identifier.") }
        return match
    }
}

// MARK: - Virtual Machine References

/// Finds the virtual machine a command-line argument refers to: its name, its identifier or the path of its bundle.
enum VMReference {
    static func resolve<Machine>(
        _ reference: String,
        in machines: [Machine],
        name: (Machine) -> String,
        uuid: (Machine) -> UUID,
        path: (Machine) -> String
    ) throws -> Machine {
        let matches: [Machine]
        if reference.contains("/") {
            let target = URL(fileURLWithPath: reference).standardizedFileURL.resolvingSymlinksInPath().path
            matches = machines.filter { URL(fileURLWithPath: path($0)).standardizedFileURL.resolvingSymlinksInPath().path == target }
        } else {
            let named = machines.filter { name($0).caseInsensitiveCompare(reference) == .orderedSame }
            if named.isEmpty, let identifier = UUID(uuidString: reference) {
                matches = machines.filter { uuid($0) == identifier }
            } else {
                matches = named
            }
        }

        guard let match = matches.first else {
            throw ControlError(.notFound, "There's no virtual machine matching \"\(reference)\" in the library. Run `vbctl list` to see the ones there are.")
        }
        guard matches.count == 1 else {
            let candidates = matches.map(path).sorted().joined(separator: "\n  ")
            throw ControlError(.ambiguous, "More than one virtual machine matches \"\(reference)\". Use the path of the one you mean:\n  \(candidates)")
        }
        return match
    }

    /// What the tool sends for an argument: paths are made absolute, because the app runs in a different folder.
    static func normalized(_ argument: String, relativeTo directory: String = FileManager.default.currentDirectoryPath) -> String {
        guard argument.contains("/") else { return argument }
        let expanded = (argument as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: directory, isDirectory: true)).standardizedFileURL.path
    }
}
