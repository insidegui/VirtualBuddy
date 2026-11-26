import AppKit
import VirtualCore
import VirtualUI
import VirtualWormhole

/// Carries out the commands of the `vbctl` command-line tool.
///
/// Nobody may be in front of the app while this runs, so nothing here presents an alert or waits for a decision:
/// whatever would need one is reported back to the tool as an error that says what to do about it.
@MainActor
final class ControlRequestHandler {
    typealias Report = @MainActor (String) async -> Void

    private let automation: VMAutomationService
    private var library: VMLibraryController { automation.library }

    init(automation: VMAutomationService) {
        self.automation = automation
    }

    func handle(_ request: ControlRequest, report: @escaping Report) async throws -> ControlPayload {
        let timeout = request.timeout

        switch request.command {
        case .list(let runningOnly):
            let machines = library.virtualMachines
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map(summary)
            return .machines(runningOnly ? machines.filter(\.isActive) : machines)
        case .status(let vm):
            guard let vm else { return .app(appStatus()) }
            return .machine(detail(for: try machine(vm)))
        case .library:
            NotificationCenter.default.post(name: .openVirtualBuddyLibraryWindow, object: nil)
            NSApp.activate()
            return .message("Opened the library.")

        case .open(let vm):
            let vm = try installedMachine(vm)
            automation.open(vm, options: nil)
            NSApp.activate()
            return .message("Opened \(vm.name.wrappedInSmartQuotes).")
        case .start(let vm, let options):
            return try await start(try installedMachine(vm), options: options, timeout: timeout, report: report)
        case .stop(let vm, let force, let wait):
            return try await stop(try machine(vm), force: force, wait: wait, timeout: timeout)
        case .pause(let vm):
            let vm = try machine(vm)
            let controller = try sessionController(for: vm)
            guard controller.canPause else { throw invalidState(vm, controller, "so it can't be paused") }
            try await controller.pause()
            return .message("Paused \(vm.name.wrappedInSmartQuotes).")
        case .resume(let vm):
            let vm = try machine(vm)
            let controller = try sessionController(for: vm)
            guard controller.canResume else { throw invalidState(vm, controller, "so there's nothing to resume. Use `vbctl start` to start it") }
            try await controller.resume()
            return .message("Resumed \(vm.name.wrappedInSmartQuotes).")
        case .save(let vm):
            let vm = try machine(vm)
            let controller = try sessionController(for: vm)
            guard controller.state.canSaveAndClose else { throw invalidState(vm, controller, "so its state can't be saved") }
            try await controller.saveAndStop()
            return .message("Saved the state of \(vm.name.wrappedInSmartQuotes) and stopped it.")

        case .guestStatus(let vm, let wait):
            let vm = try machine(vm)
            if wait { try await waitForGuest(in: try liveController(for: vm), timeout: timeout, report: report) }
            return .guest(guestStatus(for: vm))
        case .guestInfo(let vm):
            let vm = try machine(vm)
            guard let info = guestInfo(for: vm) else {
                throw ControlError(.guestUnavailable, "\(vm.name.wrappedInSmartQuotes) hasn't reported anything about its system. That takes the VirtualBuddyGuest app running in the virtual machine.")
            }
            return .guestInfo(info)
        case .guestAppearance(let vm, let change):
            return .appearance(try await appearance(of: try machine(vm), change: change, timeout: timeout))

        case .tunnelList(let vm):
            return .tunnels(tunnels(of: try machine(vm)))
        case .tunnelAdd(let vm, let listen, let destination, let wait):
            return .tunnelChange(try await addTunnel(to: try machine(vm), listen: listen, destination: destination, wait: wait, timeout: timeout, report: report))
        case .tunnelSetEnabled(let vm, let tunnel, let enabled):
            return .tunnelChange(try setTunnel(tunnel, enabled: enabled, in: try machine(vm)))
        case .tunnelRemove(let vm, let tunnel):
            return .tunnelChange(try removeTunnel(tunnel, from: try machine(vm)))
        case .tunnelDecline(let vm, let request):
            return .tunnelChange(try declineTunnel(request, in: try machine(vm)))

        case .display(let vm, let change):
            return .display(try display(of: try machine(vm), change: change))

        case .shareList(let vm):
            return .shares(shares(of: try machine(vm)))
        case .shareAdd(let vm, let path, let readOnly):
            return .shares(try addShare(path, readOnly: readOnly, to: try machine(vm)))
        case .shareRemove(let vm, let path):
            return .shares(try removeShare(path, from: try machine(vm)))

        case .networkStatus(let vm):
            return .network(network(of: try machine(vm)))
        case .networkReconnect(let vm):
            let vm = try machine(vm)
            let controller = try liveController(for: vm)
            try controller.reconnectNetwork()
            return .message("Reconnected the network of \(vm.name.wrappedInSmartQuotes).")
        case .networkBridge(let vm, let interface):
            return .network(try changeBridge(of: try machine(vm), to: interface))

        case .usbList(let vm):
            return .usb(try usbDevices(of: try machine(vm)))
        case .usbSetAttached(let vm, let device, let attached):
            return .usb(try await setUSBDevice(device, attached: attached, in: try machine(vm)))
        }
    }

    // MARK: - Lookup

    private func machine(_ reference: String) throws -> VBVirtualMachine {
        try automation.virtualMachine(matching: reference)
    }

    private func installedMachine(_ reference: String) throws -> VBVirtualMachine {
        let vm = try machine(reference)
        guard !vm.needsInstall else {
            throw ControlError(.invalidState, "\(vm.name.wrappedInSmartQuotes) hasn't finished installing. Open it in VirtualBuddy to continue the installation.")
        }
        return vm
    }

    /// The controller of a virtual machine whose window is open, whatever state it's in.
    private func sessionController(for vm: VBVirtualMachine) throws -> VMController {
        guard let controller = automation.controller(for: vm) else {
            throw ControlError(.invalidState, "\(vm.name.wrappedInSmartQuotes) isn't running.")
        }
        return controller
    }

    /// The controller of a virtual machine that's running or paused, which is when its live settings can be changed.
    private func liveController(for vm: VBVirtualMachine) throws -> VMController {
        let controller = try sessionController(for: vm)
        guard controller.state.isRunning || controller.state.isPaused else {
            throw invalidState(vm, controller, "and this needs it to be running")
        }
        return controller
    }

    private func invalidState(_ vm: VBVirtualMachine, _ controller: VMController, _ consequence: String) -> ControlError {
        ControlError(.invalidState, "\(vm.name.wrappedInSmartQuotes) is \(controller.state.controlDescription), \(consequence).")
    }

    /// The saved model of a virtual machine, as its session has it when there is one.
    private func model(of vm: VBVirtualMachine) -> VBVirtualMachine {
        automation.controller(for: vm)?.virtualMachineModel ?? vm
    }

    private func wait(
        timeout: Double?,
        expiry: @autoclosure () -> ControlError,
        until condition: () throws -> Bool
    ) async throws {
        let deadline = timeout.map { ContinuousClock.now.advanced(by: .seconds($0)) }
        while try !condition() {
            if let deadline, ContinuousClock.now >= deadline { throw expiry() }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    // MARK: - Status

    private func summary(for vm: VBVirtualMachine) -> ControlMachine {
        let controller = automation.controller(for: vm)
        let model = controller?.virtualMachineModel ?? vm

        let state: String
        if let controller {
            state = controller.state.controlName
        } else if vm.needsInstall {
            state = "not-installed"
        } else {
            state = vm.savedSession == nil ? "stopped" : "saved"
        }

        var guest: String?
        if let controller, controller.state.isRunning || controller.state.isPaused {
            guest = controller.guestAppConnectionStatus?.controlName
        }

        return ControlMachine(
            name: vm.name,
            uuid: vm.uuid,
            path: vm.bundleURL.path,
            system: vm.configuration.systemType.rawValue,
            state: state,
            detail: controller?.state.controlDetail,
            guest: guest,
            osVersion: model.guestSystemInformation?.information.osVersion
        )
    }

    private func detail(for vm: VBVirtualMachine) -> ControlMachineDetail {
        let controller = automation.controller(for: vm)
        let tunnels = tunnels(of: vm)
        return ControlMachineDetail(
            machine: summary(for: vm),
            guestInfo: guestInfo(for: vm),
            appearance: controller.flatMap { $0.guestAppearance == nil ? nil : appearance(of: $0) },
            display: currentDisplay(of: vm),
            tunnelCount: tunnels.tunnels.count,
            pendingTunnelCount: tunnels.pending.count
        )
    }

    private func appStatus() -> ControlAppStatus {
        let info = Bundle.main.infoDictionary
        let machines = library.virtualMachines.map(summary)
        return ControlAppStatus(
            version: info?["CFBundleShortVersionString"] as? String ?? "",
            build: info?["CFBundleVersion"] as? String ?? "",
            libraryPath: library.libraryURL.path,
            machineCount: machines.count,
            active: machines.filter(\.isActive).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    // MARK: - Lifecycle

    private func start(_ vm: VBVirtualMachine, options: ControlStartOptions, timeout: Double?, report: Report) async throws -> ControlPayload {
        let sessionOptions = VMSessionOptions(
            bootInRecoveryMode: options.recovery,
            bootInDFUMode: options.dfu,
            bootOnInstallDevice: options.installDevice
        )

        let controller = try automation.session(for: vm).controller

        if controller.state.isRunning || controller.state.isPaused {
            guard !sessionOptions.requestsSpecialBoot else {
                throw invalidState(vm, controller, "and it has to be stopped before it can start with different boot options")
            }
            if controller.canResume { try await controller.resume() }
        } else {
            guard controller.canStart else { throw invalidState(vm, controller, "so it can't be started right now") }

            controller.reloadSavedSession()
            controller.options = sessionOptions

            do {
                try await controller.start(discardingSavedSession: options.discardSavedState && controller.savedSession != nil, unattended: true)
            } catch SavedSessionError.discardConfirmationRequired {
                throw ControlError(.invalidState, "\(vm.name.wrappedInSmartQuotes) has a saved state, which these boot options can't continue from. Pass --discard-saved-state to delete the saved state and start anyway.")
            } catch SavedSessionError.recoveryRequired(let issue) {
                throw ControlError(.invalidState, "\(issue.explanation) Open \(vm.name.wrappedInSmartQuotes) in VirtualBuddy to decide what to do with its saved state.")
            } catch SavedSessionError.restoreFailed(let error) {
                throw ControlError(.failure, "The saved state of \(vm.name.wrappedInSmartQuotes) couldn't be restored. \(error.localizedDescription) Pass --discard-saved-state to delete the saved state and start anyway.")
            }

            guard controller.state.isRunning else {
                throw ControlError(.failure, "\(vm.name.wrappedInSmartQuotes) didn't start. It's \(controller.state.controlDescription).")
            }
        }

        if options.waitForGuest {
            try await waitForGuest(in: controller, timeout: timeout, report: report)
        }

        return .machine(detail(for: vm))
    }

    private func stop(_ vm: VBVirtualMachine, force: Bool, wait: Bool, timeout: Double?) async throws -> ControlPayload {
        let controller = try sessionController(for: vm)
        guard controller.state.isActive else { throw invalidState(vm, controller, "so there's nothing to stop") }

        if force {
            try await controller.forceStop()
            return .message("Stopped \(vm.name.wrappedInSmartQuotes).")
        }

        guard controller.state.isRunning || controller.state.isPaused else {
            throw invalidState(vm, controller, "so it can't be asked to shut down. Pass --force to stop it regardless")
        }

        // A paused guest can't act on the request.
        if controller.state.isPaused { try await controller.resume() }
        try await controller.stop()

        guard wait else { return .message("Asked \(vm.name.wrappedInSmartQuotes) to shut down.") }

        try await self.wait(
            timeout: timeout,
            expiry: ControlError(.timedOut, "\(vm.name.wrappedInSmartQuotes) is still shutting down. A guest can refuse to, for example because of unsaved documents. Pass --force to stop it regardless.")
        ) { !controller.state.isActive }

        return .message("\(vm.name.wrappedInSmartQuotes) shut down.")
    }

    // MARK: - Guest

    private func waitForGuest(in controller: VMController, timeout: Double?, report: Report) async throws {
        let name = controller.virtualMachineModel.name.wrappedInSmartQuotes

        switch controller.guestAppConnectionStatus {
        case .connected:
            return
        case .disconnected:
            break
        case .disabled:
            throw ControlError(.guestUnavailable, "The guest app is turned off in the settings of \(name).")
        case .unknown, nil:
            throw ControlError(.unsupported, "The guest system in \(name) can't run a version of VirtualBuddyGuest that connects to this Mac.")
        }

        await report("Waiting for VirtualBuddyGuest in \(name)…")

        try await wait(
            timeout: timeout,
            expiry: ControlError(.timedOut, "VirtualBuddyGuest in \(name) didn't connect in time. Log in to the virtual machine and make sure the app is running.")
        ) {
            guard controller.state.isRunning || controller.state.isPaused else {
                throw ControlError(.invalidState, "\(name) stopped before VirtualBuddyGuest connected.")
            }
            return controller.isGuestAppConnected
        }
    }

    private func guestStatus(for vm: VBVirtualMachine) -> ControlGuestStatus {
        let controller = automation.controller(for: vm)
        let isLive = controller.map { $0.state.isRunning || $0.state.isPaused } ?? false
        let status = isLive ? controller?.guestAppConnectionStatus?.controlName ?? "unsupported" : "not-running"
        return ControlGuestStatus(status: status, appVersion: model(of: vm).guestSystemInformation?.information.guestAppVersion)
    }

    private func guestInfo(for vm: VBVirtualMachine) -> ControlGuestInfo? {
        guard let record = model(of: vm).guestSystemInformation else { return nil }
        let info = record.information
        return ControlGuestInfo(
            reportedAt: record.receivedAt,
            osVersion: info.osVersion,
            osBuild: info.osBuild,
            kernelVersion: info.kernelVersion,
            computerName: info.computerName,
            architecture: info.architecture,
            processorCount: info.processorCount,
            memoryBytes: info.memoryBytes,
            bootDate: info.bootDate,
            guestAppVersion: info.guestAppVersion,
            guestAppBuild: info.guestAppBuild,
            systemIntegrityProtection: info.sipDescription
        )
    }

    private func appearance(of controller: VMController, note: String? = nil) -> ControlAppearance {
        ControlAppearance(
            darkMode: controller.guestAppearance?.isDarkModeEnabled,
            followsHost: controller.automaticallySyncGuestAppearance,
            note: note
        )
    }

    private func appearance(of vm: VBVirtualMachine, change: ControlAppearanceChange?, timeout: Double?) async throws -> ControlAppearance {
        let name = vm.name.wrappedInSmartQuotes
        let controller = try liveController(for: vm)

        guard controller.guestAppConnectionStatus == .connected else {
            throw ControlError(.guestUnavailable, "VirtualBuddyGuest isn't connected in \(name). Log in to the virtual machine and make sure the app is running.")
        }
        guard let state = controller.guestAppearance, let isDark = state.isDarkModeEnabled else {
            throw ControlError(.unsupported, "The VirtualBuddyGuest app in \(name) doesn't report its appearance. Update it from the guest additions disk.")
        }

        guard let change else { return appearance(of: controller) }

        if change == .auto {
            controller.automaticallySyncGuestAppearance = true
            return appearance(of: controller)
        }

        var note: String?
        if controller.automaticallySyncGuestAppearance {
            // An appearance that follows the host would change right back.
            controller.automaticallySyncGuestAppearance = false
            note = "\(name) no longer follows this Mac's appearance. Use `auto` to follow it again."
        }

        let target = switch change {
        case .dark: true
        case .light: false
        case .toggle, .auto: !isDark
        }

        if target != isDark {
            controller.setGuestDarkModeEnabled(target)

            try await wait(
                timeout: timeout ?? 15,
                expiry: ControlError(.timedOut, "The guest in \(name) didn't change its appearance in time.")
            ) {
                if let message = state.errorMessage { throw ControlError(.failure, message) }
                return state.isDarkModeEnabled == target && !state.isUpdating
            }
        }

        return appearance(of: controller, note: note)
    }

    // MARK: - Service Tunnels

    private func tunnels(of vm: VBVirtualMachine) -> ControlTunnels {
        let controller = automation.controller(for: vm)
        let live = controller?.tunnelState
        let status = live?.status ?? [:]

        func described(_ tunnels: [ServiceTunnel]) -> [ControlTunnel] {
            tunnels.map { ControlTunnel($0, status: status[$0.id]) }
        }

        let pending = described(live?.requests ?? [])

        switch model(of: vm).serviceTunnelSettings {
        case .missing:
            return ControlTunnels(review: "none", detail: nil, tunnels: [], pending: pending)
        case .approved(let tunnels):
            return ControlTunnels(review: "approved", detail: nil, tunnels: described(tunnels), pending: pending)
        case .needsApproval(let tunnels):
            return ControlTunnels(
                review: "needs-review",
                detail: "These tunnels don't run until they're reviewed in the virtual machine's settings in VirtualBuddy.",
                tunnels: described(tunnels),
                pending: pending
            )
        case .unavailable(let reason):
            return ControlTunnels(review: "unavailable", detail: reason, tunnels: [], pending: pending)
        }
    }

    /// The approved tunnels, which are the only ones the tool can change.
    private func approvedTunnels(of vm: VBVirtualMachine) throws -> [ServiceTunnel] {
        switch model(of: vm).serviceTunnelSettings {
        case .missing: return []
        case .approved(let tunnels): return tunnels
        case .needsApproval:
            throw ControlError(.reviewRequired, "The service tunnels of \(vm.name.wrappedInSmartQuotes) have to be reviewed in its settings in VirtualBuddy before they can be changed.")
        case .unavailable(let reason):
            throw ControlError(.failure, reason)
        }
    }

    private func requireTunnelSupport(for vm: VBVirtualMachine) throws {
        guard vm.configuration.systemType == .mac else {
            throw ControlError(.unsupported, "Service tunnels need a macOS guest.")
        }
    }

    private func addTunnel(
        to vm: VBVirtualMachine,
        listen: TunnelSide,
        destination: TunnelSide,
        wait: Bool,
        timeout: Double?,
        report: Report
    ) async throws -> ControlTunnelChange {
        try requireTunnelSupport(for: vm)
        let name = vm.name.wrappedInSmartQuotes

        guard let tunnel = ServiceTunnel(listen: listen, destination: destination) else {
            throw ControlError(.failure, "A tunnel listens on one side and connects to the other, so one end has to be on the host and the other in the guest.")
        }
        if let restriction = VirtualBuddyManagedPreferences.serviceTunnelPolicy().restriction(on: tunnel) {
            throw ControlError(.restrictedByOrganization, restriction.explanation)
        }
        guard tunnel.canAdd(to: model(of: vm).serviceTunnelSettings.reviewValue ?? []) else {
            throw ControlError(.failure, "\(name) already has a tunnel that listens on \(listen), or has as many tunnels as it can.")
        }

        let controller = automation.controller(for: vm)
        let outcome: ServiceTunnelProposalOutcome
        if let controller {
            outcome = try controller.proposeTunnel(tunnel)
        } else {
            outcome = try vm.addServiceTunnelWithoutReview(tunnel) ? .added : .reviewRequired
        }

        let described = ControlTunnel(tunnel, status: nil)

        switch outcome {
        case .added:
            return ControlTunnelChange(outcome: "added", tunnel: described)
        case .reviewRequired:
            throw ControlError(.reviewRequired, "This tunnel has to be reviewed before it's used. Add it in the settings of \(name) in VirtualBuddy, or start the virtual machine with VirtualBuddyGuest running and add it again to review it there.")
        case .awaitingReview:
            // Reviewing is done in the window that lists the requested tunnels, so it's put in front of the user.
            automation.sessionManager.session(for: vm)?.openLiveServiceTunnels()

            guard wait, let controller else {
                return ControlTunnelChange(outcome: "awaiting-review", tunnel: described)
            }

            await report("Waiting for the tunnel to be reviewed in VirtualBuddy…")

            try await self.wait(
                timeout: timeout,
                expiry: ControlError(.timedOut, "The tunnel is still waiting to be reviewed in VirtualBuddy.")
            ) {
                guard let state = controller.tunnelState, state.available else {
                    throw ControlError(.guestUnavailable, "VirtualBuddyGuest disconnected from \(name) before the tunnel was reviewed, so the request is gone.")
                }
                if state.rules.contains(where: { $0.listensOnHost == tunnel.listensOnHost && $0.listener == tunnel.listener }) { return true }
                guard state.requests.contains(where: { $0.id == tunnel.id }) else {
                    throw ControlError(.reviewRequired, "The tunnel was declined in VirtualBuddy.")
                }
                return false
            }

            return ControlTunnelChange(outcome: "added", tunnel: described)
        }
    }

    private func setTunnel(_ reference: String, enabled: Bool, in vm: VBVirtualMachine) throws -> ControlTunnelChange {
        try requireTunnelSupport(for: vm)
        var tunnel = try ServiceTunnel.resolve(reference, in: approvedTunnels(of: vm))
        let controller = automation.controller(for: vm)

        if enabled {
            if let restriction = VirtualBuddyManagedPreferences.serviceTunnelPolicy().restriction(on: tunnel) {
                throw ControlError(.restrictedByOrganization, restriction.explanation)
            }
            let didEnable = try controller?.enableTunnelWithoutReview(tunnel.id) ?? vm.enableServiceTunnelWithoutReview(tunnel.id)
            guard didEnable else {
                throw ControlError(.reviewRequired, "Turning this tunnel on has to be reviewed. Turn it on in the settings of \(vm.name.wrappedInSmartQuotes) in VirtualBuddy.")
            }
        } else {
            let change: (inout [ServiceTunnel]) -> Void = { tunnels in
                guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { return }
                tunnels[index].isEnabled = false
            }
            if let controller { try controller.reduceTunnels(change) } else { try vm.reduceApprovedServiceTunnels(change) }
        }

        tunnel.isEnabled = enabled
        return ControlTunnelChange(outcome: enabled ? "enabled" : "disabled", tunnel: ControlTunnel(tunnel, status: nil))
    }

    private func removeTunnel(_ reference: String, from vm: VBVirtualMachine) throws -> ControlTunnelChange {
        try requireTunnelSupport(for: vm)
        let tunnel = try ServiceTunnel.resolve(reference, in: approvedTunnels(of: vm))
        let change: (inout [ServiceTunnel]) -> Void = { $0.removeAll { $0.id == tunnel.id } }
        if let controller = automation.controller(for: vm) { try controller.reduceTunnels(change) } else { try vm.reduceApprovedServiceTunnels(change) }
        return ControlTunnelChange(outcome: "removed", tunnel: ControlTunnel(tunnel, status: nil))
    }

    private func declineTunnel(_ reference: String, in vm: VBVirtualMachine) throws -> ControlTunnelChange {
        let controller = try liveController(for: vm)
        let request = try ServiceTunnel.resolve(reference, in: controller.tunnelState?.requests ?? [])
        controller.declineTunnel(request.id)
        return ControlTunnelChange(outcome: "declined", tunnel: ControlTunnel(request, status: nil))
    }

    // MARK: - Display

    private func currentDisplay(of vm: VBVirtualMachine) -> ControlDisplay? {
        let configuration = automation.controller(for: vm)?.liveConfiguration ?? vm.configuration
        return configuration.hardware.displayDevices.first.map(ControlDisplay.init)
    }

    private func display(of vm: VBVirtualMachine, change: ControlDisplayChange) throws -> ControlDisplay {
        let name = vm.name.wrappedInSmartQuotes

        guard !change.isEmpty else {
            guard let display = currentDisplay(of: vm) else { throw ControlError(.unsupported, "\(name) doesn't have a display.") }
            return display
        }

        let controller = try liveController(for: vm)
        guard controller.canEditLiveDisplay, var device = controller.liveConfiguration.hardware.displayDevices.first else {
            throw ControlError(.unsupported, "The display of \(name) can't be changed while it's running. That takes macOS 14 or later on this Mac, and the virtual machine not being in the middle of something else.")
        }

        if let width = change.width { device.width = width }
        if let height = change.height { device.height = height }
        if let pixelsPerInch = change.pixelsPerInch { device.pixelsPerInch = pixelsPerInch }
        if let automaticallyResizes = change.automaticallyResizes { device.automaticallyReconfiguresDisplay = automaticallyResizes }

        try controller.updateLiveDisplay(device)

        return controller.liveConfiguration.hardware.displayDevices.first.map(ControlDisplay.init) ?? ControlDisplay(device)
    }

    // MARK: - Shared Folders

    private func shares(of vm: VBVirtualMachine) -> [ControlShare] {
        let configuration = automation.controller(for: vm)?.liveConfiguration ?? vm.configuration
        return configuration.sharedFolders.map {
            ControlShare(path: $0.url.path, name: $0.effectiveMountPointName, readOnly: $0.isReadOnly, enabled: $0.isEnabled)
        }
    }

    private func sharesController(for vm: VBVirtualMachine) throws -> VMController {
        let controller = try liveController(for: vm)
        guard controller.canEditLiveSharedFolders else {
            throw ControlError(.unsupported, "The shared folders of \(vm.name.wrappedInSmartQuotes) can't be changed while it's running. It has to start with shared folders available, and not be in the middle of something else.")
        }
        return controller
    }

    private func addShare(_ path: String, readOnly: Bool, to vm: VBVirtualMachine) throws -> [ControlShare] {
        let controller = try sharesController(for: vm)
        var configuration = controller.liveConfiguration
        let folder = try configuration.addSharedFolder(with: URL(fileURLWithPath: path).standardizedFileURL)
        if readOnly, let index = configuration.sharedFolders.firstIndex(where: { $0.id == folder.id }) {
            configuration.sharedFolders[index].isReadOnly = true
        }
        try controller.updateLiveSharedFolders(configuration.sharedFolders)
        return shares(of: vm)
    }

    private func removeShare(_ path: String, from vm: VBVirtualMachine) throws -> [ControlShare] {
        let controller = try sharesController(for: vm)
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        var folders = controller.liveConfiguration.sharedFolders
        guard folders.contains(where: { $0.url.standardizedFileURL.path == target }) else {
            throw ControlError(.notFound, "\(target) isn't shared with \(vm.name.wrappedInSmartQuotes).")
        }
        folders.removeAll { $0.url.standardizedFileURL.path == target }
        try controller.updateLiveSharedFolders(folders)
        return shares(of: vm)
    }

    // MARK: - Network

    private func network(of vm: VBVirtualMachine) -> ControlNetwork {
        let controller = automation.controller(for: vm)
        let configuration = controller?.liveConfiguration ?? vm.configuration
        let active = controller?.activeBridgeInterfaceIdentifiers ?? []
        return ControlNetwork(
            devices: configuration.hardware.networkDevices.map {
                ControlNetwork.Device(name: $0.name, kind: $0.kind == .NAT ? "nat" : "bridge", macAddress: $0.macAddress)
            },
            bridgeInterfaces: (controller?.availableBridgeInterfaces ?? []).map {
                ControlNetwork.Interface(id: $0.id, name: $0.name, active: active.contains($0.id))
            },
            canChangeBridgeInterface: controller?.canChangeBridgeInterface ?? false
        )
    }

    private func changeBridge(of vm: VBVirtualMachine, to reference: String) throws -> ControlNetwork {
        let controller = try liveController(for: vm)
        guard controller.canChangeBridgeInterface else {
            throw ControlError(.unsupported, "\(vm.name.wrappedInSmartQuotes) doesn't have a bridged network device.")
        }
        let interfaces = controller.availableBridgeInterfaces
        let matches = interfaces.filter { $0.id.caseInsensitiveCompare(reference) == .orderedSame }
        let named = matches.isEmpty ? interfaces.filter { $0.name.caseInsensitiveCompare(reference) == .orderedSame } : matches
        guard let interface = named.first else {
            throw ControlError(.notFound, "This Mac doesn't have a network interface called \"\(reference)\" that can be bridged. Run `vbctl network status` to see the ones it has.")
        }
        guard named.count == 1 else {
            throw ControlError(.ambiguous, "More than one network interface is called \"\(reference)\". Use its identifier, such as en0.")
        }
        try controller.changeBridgeInterface(to: interface.id)
        return network(of: vm)
    }

    // MARK: - USB

    private func usbDevices(of vm: VBVirtualMachine) throws -> [ControlUSBDevice] {
        guard #available(macOS 27.0, *) else {
            throw ControlError(.unsupported, "Attaching USB devices to virtual machines requires macOS 27 or later.")
        }
        let controller = try liveController(for: vm)
        return (controller.usbDeviceController?.devices ?? []).map(ControlUSBDevice.init)
    }

    private func setUSBDevice(_ reference: String, attached: Bool, in vm: VBVirtualMachine) async throws -> [ControlUSBDevice] {
        guard #available(macOS 27.0, *) else {
            throw ControlError(.unsupported, "Attaching USB devices to virtual machines requires macOS 27 or later.")
        }
        let controller = try liveController(for: vm)
        guard let usb = controller.usbDeviceController else {
            throw ControlError(.unsupported, "\(vm.name.wrappedInSmartQuotes) can't have USB devices attached.")
        }

        let matches = usb.devices.filter { ControlUSBDevice($0).matches(reference) }
        guard let device = matches.first else {
            throw ControlError(.notFound, "There's no USB device matching \"\(reference)\". Run `vbctl usb list` to see the ones there are.")
        }
        guard matches.count == 1 else {
            throw ControlError(.ambiguous, "More than one USB device matches \"\(reference)\". Use its identifier from `vbctl usb list`.")
        }

        if device.isAttached != attached {
            try await usb.toggleAttachment(for: device.id)
        }

        return usb.devices.map(ControlUSBDevice.init)
    }
}

// MARK: - Descriptions

private extension ControlMachine {
    var isActive: Bool {
        switch state {
        case "starting", "running", "paused", "saving", "restoring": true
        default: false
        }
    }
}

extension VMState {
    /// The state as scripts see it.
    var controlName: String {
        switch self {
        case .idle, .stopped: "stopped"
        case .starting, .resizingDisk: "starting"
        case .running: "running"
        case .paused: "paused"
        case .saving: "saving"
        case .restoring: "restoring"
        case .saved: "saved"
        case .recoveryRequired: "recovery-required"
        }
    }

    var controlDetail: String? {
        switch self {
        case .starting(let message), .resizingDisk(let message): message
        case .saving(_, let phase), .restoring(_, let phase): phase.title
        case .stopped(let error): error?.localizedDescription
        case .recoveryRequired(let issue): issue.explanation
        case .idle, .running, .paused, .saved: nil
        }
    }

    /// The state as it reads in a sentence: "… is stopped".
    var controlDescription: String {
        switch self {
        case .idle, .stopped: "stopped"
        case .starting, .resizingDisk: "starting up"
        case .running: "running"
        case .paused: "paused"
        case .saving: "saving its state"
        case .restoring: "restoring its saved state"
        case .saved: "stopped with a saved state"
        case .recoveryRequired: "stopped with a saved state that needs attention"
        }
    }
}

private extension GuestAppConnectionStatus {
    var controlName: String {
        switch self {
        case .disabled: "disabled"
        case .unknown: "unknown"
        case .disconnected: "disconnected"
        case .connected: "connected"
        }
    }
}

private extension ControlTunnel {
    init(_ tunnel: ServiceTunnel, status: String?) {
        self.init(
            id: tunnel.id,
            listen: tunnel.listenSide.description,
            destination: tunnel.destinationSide.description,
            enabled: tunnel.isEnabled,
            status: status
        )
    }
}

private extension ControlDisplay {
    init(_ device: VBDisplayDevice) {
        self.init(
            width: device.width,
            height: device.height,
            pixelsPerInch: device.pixelsPerInch,
            automaticallyResizes: device.automaticallyReconfiguresDisplay
        )
    }
}

@available(macOS 27.0, *)
private extension ControlUSBDevice {
    init(_ device: VMUSBDeviceController.Device) {
        self.init(
            id: String(format: "0x%llx", device.id),
            name: device.productName ?? "USB Device",
            vendorID: String(format: "%04x", device.vendorID),
            productID: String(format: "%04x", device.productID),
            attached: device.isAttached,
            error: device.errorMessage
        )
    }

    /// A device is referred to by its identifier, by `vendor:product`, or by its name.
    func matches(_ reference: String) -> Bool {
        let reference = reference.lowercased()
        return reference == id || reference == "\(vendorID):\(productID)" || reference == name.lowercased()
    }
}
