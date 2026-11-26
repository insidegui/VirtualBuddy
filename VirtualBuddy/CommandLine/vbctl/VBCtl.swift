import ArgumentParser
import Foundation

/// Controls VirtualBuddy and its virtual machines from the command line.
///
/// The tool is the app's own executable under another name. It does nothing by itself: every command is
/// sent to the running app over the control socket, which only exists while command-line access is enabled.
struct VBCtl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vbctl",
        abstract: "Control VirtualBuddy and its virtual machines.",
        discussion: """
        Command-line access has to be enabled in VirtualBuddy Settings → Security. VirtualBuddy is opened in the \
        background when it isn't running.

        A virtual machine is referred to by its name, its UUID or the path of its bundle.

        Exit codes: 1 failure, 3 command-line access unavailable, 4 not found or ambiguous, 5 wrong state, \
        6 guest app unavailable or feature unsupported, 7 timed out, 8 needs review or restricted by your organization.
        """,
        subcommands: [
            List.self, Status.self, Library.self,
            Open.self, Start.self, Stop.self, Pause.self, Resume.self, Save.self,
            Guest.self, Tunnel.self, Display.self, Share.self, Network.self, USB.self,
        ]
    )
}

// MARK: - Shared Arguments

struct ControlOptions: ParsableArguments {
    @Flag(name: .long, help: "Print the result as JSON.")
    var json = false

    @Flag(name: .shortAndLong, help: "Don't print progress or confirmations.")
    var quiet = false

    @Option(name: .long, help: ArgumentHelp("Give up waiting after this many seconds.", valueName: "seconds"))
    var timeout: Double?

    @Flag(name: .long, help: "Fail instead of opening VirtualBuddy when it isn't running.")
    var noLaunch = false

    func validate() throws {
        if let timeout, timeout <= 0 { throw ValidationError("The timeout has to be more than zero seconds.") }
    }

    /// Sends the command to the app and prints what it answers. Failures end the tool with the exit code that stands for them.
    @MainActor
    func run(_ command: ControlCommand) async throws {
        do {
            let payload = try await ControlClient.perform(
                ControlRequest(command: command, timeout: timeout),
                launchingApp: !noLaunch,
                onEvent: { if !quiet && !json { Self.printError($0) } }
            )

            if json {
                print(try ControlOutput.json(payload))
            } else if !(quiet && ControlOutput.isConfirmation(payload)) {
                print(ControlOutput.text(payload))
            }

            if case .appearance(let appearance) = payload, let note = appearance.note, !quiet, !json {
                Self.printError(note)
            }
            // The command did what it could, but the tunnel isn't usable until someone reviews it.
            if case .tunnelChange(let change) = payload, change.outcome == "awaiting-review" {
                throw ExitCode(ControlError(.reviewRequired, "").exitCode)
            }
        } catch let error as ControlError {
            Self.printError(json ? ControlOutput.json(error) : "vbctl: \(error.message)")
            throw ExitCode(error.exitCode)
        }
    }

    private static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

struct MachineArgument: ParsableArguments {
    @Argument(help: ArgumentHelp("The virtual machine's name, UUID or bundle path.", valueName: "vm"))
    var machine: String

    var reference: String { VMReference.normalized(machine) }
}

extension TunnelSide: ExpressibleByArgument {
    init?(argument: String) { self.init(argument) }
}

extension ControlAppearanceChange: ExpressibleByArgument { }

enum OnOff: String, ExpressibleByArgument, CaseIterable {
    case on, off
}

struct DisplaySize: ExpressibleByArgument {
    var width: Int
    var height: Int

    init?(argument: String) {
        let parts = argument.lowercased().split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]), width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
    }
}

// MARK: - App and Library

extension VBCtl {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the virtual machines in the library.", aliases: ["ls"])

        @Flag(name: .long, help: "Only list virtual machines that are running.")
        var running = false

        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.list(runningOnly: running)) }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the status of VirtualBuddy, or of a virtual machine.")

        @Argument(help: ArgumentHelp("The virtual machine's name, UUID or bundle path. Shows the app's status when left out.", valueName: "vm"))
        var machine: String?

        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.status(vm: machine.map { VMReference.normalized($0) })) }
    }

    struct Library: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open the library window.")

        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.library) }
    }
}

// MARK: - Lifecycle

extension VBCtl {
    struct Open: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open a virtual machine's window without starting it.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.open(vm: machine.reference)) }
    }

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Start a virtual machine.",
            discussion: "Continues from the saved state if there is one, and resumes the virtual machine if it's paused. Returns once it's running.",
            aliases: ["boot"]
        )

        @OptionGroup var machine: MachineArgument

        @Flag(name: .long, help: "Start in recovery mode.")
        var recovery = false

        @Flag(name: .long, help: "Start in DFU mode.")
        var dfu = false

        @Flag(name: .long, help: "Start from the install device.")
        var installDevice = false

        @Flag(name: .long, help: "Delete the saved state instead of continuing from it.")
        var discardSavedState = false

        @Flag(name: .long, help: "Wait until the VirtualBuddyGuest app in the virtual machine has connected.")
        var waitForGuest = false

        @OptionGroup var options: ControlOptions

        func validate() throws {
            if recovery && dfu { throw ValidationError("A virtual machine can start in recovery mode or in DFU mode, not both.") }
        }

        func run() async throws {
            let start = ControlStartOptions(
                recovery: recovery,
                dfu: dfu,
                installDevice: installDevice,
                discardSavedState: discardSavedState,
                waitForGuest: waitForGuest
            )
            try await options.run(.start(vm: machine.reference, options: start))
        }
    }

    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Shut down a virtual machine.",
            discussion: "Asks the guest to shut down, which it may take a while to do, or refuse."
        )

        @OptionGroup var machine: MachineArgument

        @Flag(name: .long, help: "Stop immediately, without giving the guest a chance to shut down. This can lose data.")
        var force = false

        @Flag(name: .long, help: "Wait until the virtual machine has shut down.")
        var wait = false

        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.stop(vm: machine.reference, force: force, wait: wait)) }
    }

    struct Pause: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Pause a running virtual machine.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.pause(vm: machine.reference)) }
    }

    struct Resume: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Resume a paused virtual machine.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.resume(vm: machine.reference)) }
    }

    struct Save: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Save a virtual machine's state and stop it.",
            discussion: "The next start continues from where it was saved."
        )

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.save(vm: machine.reference)) }
    }
}

// MARK: - Guest

extension VBCtl {
    struct Guest: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Use features of the VirtualBuddyGuest app in a virtual machine.",
            subcommands: [GuestStatus.self, GuestInfo.self, GuestAppearance.self]
        )
    }

    struct GuestStatus: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show whether the VirtualBuddyGuest app is connected."
        )

        @OptionGroup var machine: MachineArgument

        @Flag(name: .long, help: "Wait until the app has connected.")
        var wait = false

        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.guestStatus(vm: machine.reference, wait: wait)) }
    }

    struct GuestInfo: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Show what the guest last reported about its system."
        )

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.guestInfo(vm: machine.reference)) }
    }

    struct GuestAppearance: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "appearance",
            abstract: "Show or change whether the guest uses dark mode.",
            discussion: "`auto` makes the guest follow this Mac's appearance. Choosing an appearance stops it from doing that."
        )

        @OptionGroup var machine: MachineArgument

        @Argument(help: "The appearance to change to. Shows the current one when left out.")
        var appearance: ControlAppearanceChange?

        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.guestAppearance(vm: machine.reference, change: appearance)) }
    }
}

// MARK: - Service Tunnels

extension VBCtl {
    struct Tunnel: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage service tunnels between this Mac and a virtual machine.",
            discussion: """
            An end of a tunnel is written as the side it's on and a TCP port or Unix socket path: host:8080, \
            guest:tcp6:8080, host:/tmp/service.sock. Ports are on the loopback interface.

            Tunnels are subject to the review chosen in VirtualBuddy Settings → Security. A tunnel that has to be \
            reviewed is never approved from the command line: it waits in VirtualBuddy, and the command exits with code 8.
            """,
            subcommands: [TunnelList.self, TunnelAdd.self, TunnelEnable.self, TunnelDisable.self, TunnelRemove.self, TunnelDecline.self]
        )
    }

    struct TunnelList: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List a virtual machine's tunnels, and the ones waiting for review.",
            aliases: ["ls"]
        )

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.tunnelList(vm: machine.reference)) }
    }

    struct TunnelAdd: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a tunnel that listens on one side and connects to a service on the other.",
            discussion: """
            vbctl tunnel add Sequoia host:8080 guest:80 lets this Mac reach the guest's port 80 at localhost:8080.
            vbctl tunnel add Sequoia guest:5432 host:5432 lets the guest reach a database running on this Mac.
            """
        )

        @OptionGroup var machine: MachineArgument

        @Argument(help: ArgumentHelp("Where the tunnel listens.", valueName: "listen"))
        var listen: TunnelSide

        @Argument(help: ArgumentHelp("The service the tunnel connects to, on the other side.", valueName: "destination"))
        var destination: TunnelSide

        @Flag(name: .long, help: "Wait until the tunnel has been reviewed in VirtualBuddy, if it has to be.")
        var wait = false

        @OptionGroup var options: ControlOptions

        func validate() throws {
            if listen.onHost == destination.onHost {
                throw ValidationError("One end of the tunnel has to be on the host and the other in the guest.")
            }
        }

        func run() async throws {
            try await options.run(.tunnelAdd(vm: machine.reference, listen: listen, destination: destination, wait: wait))
        }
    }

    struct TunnelReference: ParsableArguments {
        @Argument(help: ArgumentHelp("The end the tunnel listens on, such as host:8080, or the start of its ID.", valueName: "tunnel"))
        var tunnel: String
    }

    struct TunnelEnable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "enable", abstract: "Turn a tunnel on.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var tunnel: TunnelReference
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.tunnelSetEnabled(vm: machine.reference, tunnel: tunnel.tunnel, enabled: true)) }
    }

    struct TunnelDisable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "disable", abstract: "Turn a tunnel off without removing it.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var tunnel: TunnelReference
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.tunnelSetEnabled(vm: machine.reference, tunnel: tunnel.tunnel, enabled: false)) }
    }

    struct TunnelRemove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a tunnel.", aliases: ["rm"])

        @OptionGroup var machine: MachineArgument
        @OptionGroup var tunnel: TunnelReference
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.tunnelRemove(vm: machine.reference, tunnel: tunnel.tunnel)) }
    }

    struct TunnelDecline: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "decline", abstract: "Decline a tunnel that's waiting for review.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var tunnel: TunnelReference
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.tunnelDecline(vm: machine.reference, request: tunnel.tunnel)) }
    }
}

// MARK: - Live Settings

extension VBCtl {
    struct Display: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show or change the display of a virtual machine.",
            discussion: "Changes apply to the running virtual machine right away, and are saved with it."
        )

        @OptionGroup var machine: MachineArgument

        @Option(name: .long, help: ArgumentHelp("The resolution in pixels, such as 1920x1080.", valueName: "widthxheight"))
        var size: DisplaySize?

        @Option(name: .long, help: "The pixel density, in pixels per inch.")
        var ppi: Int?

        @Option(name: .long, help: "Whether the display follows the size of the virtual machine's window.")
        var autoResize: OnOff?

        @OptionGroup var options: ControlOptions

        func run() async throws {
            let change = ControlDisplayChange(
                width: size?.width,
                height: size?.height,
                pixelsPerInch: ppi,
                automaticallyResizes: autoResize.map { $0 == .on }
            )
            try await options.run(.display(vm: machine.reference, change: change))
        }
    }

    struct Share: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage the folders shared with a running virtual machine.",
            subcommands: [ShareList.self, ShareAdd.self, ShareRemove.self]
        )
    }

    struct ShareList: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List the shared folders.", aliases: ["ls"])

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.shareList(vm: machine.reference)) }
    }

    struct FolderArgument: ParsableArguments {
        @Argument(help: ArgumentHelp("A folder on this Mac.", valueName: "path"), completion: .directory)
        var path: String

        /// The app runs in a different folder, so it gets the whole path.
        var absolutePath: String {
            let expanded = (path as NSString).expandingTildeInPath
            let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            return URL(fileURLWithPath: expanded, relativeTo: base).standardizedFileURL.path
        }
    }

    struct ShareAdd: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "Share a folder with the virtual machine.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var folder: FolderArgument

        @Flag(name: .long, help: "Don't let the guest change the folder's contents.")
        var readOnly = false

        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.shareAdd(vm: machine.reference, path: folder.absolutePath, readOnly: readOnly)) }
    }

    struct ShareRemove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "Stop sharing a folder.", aliases: ["rm"])

        @OptionGroup var machine: MachineArgument
        @OptionGroup var folder: FolderArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.shareRemove(vm: machine.reference, path: folder.absolutePath)) }
    }

    struct Network: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage the network of a running virtual machine.",
            subcommands: [NetworkStatus.self, NetworkReconnect.self, NetworkBridge.self]
        )
    }

    struct NetworkStatus: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show the network devices, and the host interfaces a bridged device can use."
        )

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.networkStatus(vm: machine.reference)) }
    }

    struct NetworkReconnect: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "reconnect", abstract: "Reconnect the network devices.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.networkReconnect(vm: machine.reference)) }
    }

    struct NetworkBridge: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "bridge",
            abstract: "Bridge the virtual machine's network device onto another host interface."
        )

        @OptionGroup var machine: MachineArgument

        @Argument(help: ArgumentHelp("The identifier or name of a host interface, such as en0.", valueName: "interface"))
        var interface: String

        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.networkBridge(vm: machine.reference, interface: interface)) }
    }

    struct USB: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "usb",
            abstract: "Attach USB devices connected to this Mac to a running virtual machine.",
            subcommands: [USBList.self, USBAttach.self, USBDetach.self]
        )
    }

    struct USBList: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List the USB devices that can be attached.", aliases: ["ls"])

        @OptionGroup var machine: MachineArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.usbList(vm: machine.reference)) }
    }

    struct USBDeviceArgument: ParsableArguments {
        @Argument(help: ArgumentHelp("The device's ID, vendor:product pair or name, as shown by `vbctl usb list`.", valueName: "device"))
        var device: String
    }

    struct USBAttach: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "attach", abstract: "Attach a USB device to the virtual machine.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var device: USBDeviceArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.usbSetAttached(vm: machine.reference, device: device.device, attached: true)) }
    }

    struct USBDetach: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "detach", abstract: "Detach a USB device from the virtual machine.")

        @OptionGroup var machine: MachineArgument
        @OptionGroup var device: USBDeviceArgument
        @OptionGroup var options: ControlOptions

        func run() async throws { try await options.run(.usbSetAttached(vm: machine.reference, device: device.device, attached: false)) }
    }
}
