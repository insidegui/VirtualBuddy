import Foundation
import OSLog
import SystemConfiguration
import Virtualization

private func vmNetworkAttachmentDynamicStoreCallback(
    _ store: SCDynamicStore,
    changedKeys: CFArray,
    info: UnsafeMutableRawPointer?
) {
    guard let info else { return }

    MainActor.assumeIsolated {
        let helper = Unmanaged<VMNetworkAttachmentHelper>.fromOpaque(info).takeUnretainedValue()
        let keys = (changedKeys as NSArray).compactMap { $0 as? String }
        helper.dynamicStoreDidChange(keys)
    }
}

@MainActor
final class VMNetworkAttachmentHelper {
    private struct AttachmentConfiguration {
        enum Kind {
            case NAT
            case bridge(interfaceIdentifier: String)
        }

        var kind: Kind
        let macAddress: String

        var bridgeInterfaceIdentifier: String? {
            guard case .bridge(let interfaceIdentifier) = kind else { return nil }
            return interfaceIdentifier
        }

        var description: String {
            switch kind {
            case .NAT:
                return "NAT"
            case .bridge(let interfaceIdentifier):
                return "bridge(\(interfaceIdentifier))"
            }
        }

        func makeAttachment() throws -> VZNetworkDeviceAttachment {
            switch kind {
            case .NAT:
                return VZNATNetworkDeviceAttachment()
            case .bridge(let interfaceIdentifier):
                guard let interface = VZBridgedNetworkInterface.networkInterfaces.first(where: {
                    $0.identifier == interfaceIdentifier
                }) else {
                    throw Failure("The bridged network interface \(interfaceIdentifier.quoted) is not currently available.")
                }

                return VZBridgedNetworkDeviceAttachment(interface: interface)
            }
        }
    }

    private struct RecoveryTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    private enum RecoveryReason: String {
        case attachmentDisconnected
        case bridgeInterfaceChanged
        case hostInterfaceBecameActive
        case manualRequest
    }

    private static let recoveryDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30]
    private static let attachmentStabilizationDelay: TimeInterval = 1
    private static let hostInterfaceDebounceDelay: TimeInterval = 1

    private let virtualMachine: VZVirtualMachine
    private let logger: Logger
    private var attachmentConfigurations: [AttachmentConfiguration?]

    private var recoveryTasks: [Int: RecoveryTask] = [:]

    private var dynamicStore: SCDynamicStore?
    private var interfaceIdentifierByLinkKey: [String: String] = [:]
    private var interfaceLinkStates: [String: Bool] = [:]

    init(
        virtualMachine: VZVirtualMachine,
        configuration: VZVirtualMachineConfiguration,
        logger: Logger
    ) {
        self.virtualMachine = virtualMachine
        self.logger = logger
        self.attachmentConfigurations = configuration.networkDevices.enumerated().map { index, device in
            guard let attachment = device.attachment else {
                logger.error("Network device \(index) has no attachment; automatic recovery will be unavailable for this device")
                return nil
            }

            let kind: AttachmentConfiguration.Kind

            switch attachment {
            case is VZNATNetworkDeviceAttachment:
                kind = .NAT
            case let bridge as VZBridgedNetworkDeviceAttachment:
                kind = .bridge(interfaceIdentifier: bridge.interface.identifier)
            default:
                logger.error("Network device \(index) uses unsupported attachment type \(String(describing: type(of: attachment)), privacy: .public); automatic recovery will be unavailable for this device")
                return nil
            }

            return AttachmentConfiguration(
                kind: kind,
                macAddress: device.macAddress.string.uppercased()
            )
        }

        if virtualMachine.networkDevices.count != configuration.networkDevices.count {
            logger.error("Runtime network device count \(virtualMachine.networkDevices.count) does not match configuration count \(configuration.networkDevices.count)")
        }
    }

    func startMonitoringHostInterfaces() {
        guard dynamicStore == nil else { return }

        let interfaceIdentifiers = Set(attachmentConfigurations.compactMap { $0?.bridgeInterfaceIdentifier })
        guard !interfaceIdentifiers.isEmpty else { return }

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let store = SCDynamicStoreCreate(
            nil,
            "VirtualBuddy.VMNetworkAttachmentHelper" as CFString,
            vmNetworkAttachmentDynamicStoreCallback,
            &context
        ) else {
            logger.error("Failed to create SystemConfiguration dynamic store for bridge monitoring: error=\(SCError())")
            return
        }

        let linkKeyPairs = interfaceIdentifiers.map { interfaceIdentifier in
            let key = Self.linkStateKey(for: interfaceIdentifier)
            return (key, interfaceIdentifier)
        }
        let identifierByKey = Dictionary(uniqueKeysWithValues: linkKeyPairs)
        let notificationKeys = Array(identifierByKey.keys)

        guard SCDynamicStoreSetNotificationKeys(store, notificationKeys as CFArray, nil) else {
            logger.error("Failed to register bridge link-state notifications: error=\(SCError())")
            return
        }

        let initialLinkStates = Dictionary(uniqueKeysWithValues: interfaceIdentifiers.map {
            ($0, Self.isLinkActive(interfaceIdentifier: $0, store: store))
        })

        dynamicStore = store
        interfaceIdentifierByLinkKey = identifierByKey
        interfaceLinkStates = initialLinkStates

        guard SCDynamicStoreSetDispatchQueue(store, .main) else {
            logger.error("Failed to schedule bridge link-state notifications: error=\(SCError())")
            stopMonitoringHostInterfaces()
            return
        }

        let monitoredInterfaces = interfaceIdentifiers.sorted().joined(separator: ", ")
        logger.info("Monitoring host link state for bridged interface(s): \(monitoredInterfaces, privacy: .public)")
    }

    func stop() {
        cancelRecoveryTasks()
        stopMonitoringHostInterfaces()
    }

    func reconnectAll() throws {
        var scheduledDeviceCount = 0

        for deviceIndex in virtualMachine.networkDevices.indices {
            guard attachmentConfigurations.indices.contains(deviceIndex),
                  attachmentConfigurations[deviceIndex] != nil
            else { continue }

            scheduleRecovery(
                forDeviceAt: deviceIndex,
                replacingCurrentAttachment: true,
                initialDelay: 0,
                reason: .manualRequest
            )
            scheduledDeviceCount += 1
        }

        guard scheduledDeviceCount > 0 else {
            throw Failure("This virtual machine has no network attachments that can be reconnected.")
        }

        logger.info("Manual network reconnection scheduled for \(scheduledDeviceCount) device(s)")
    }

    var bridgeInterfaceIdentifiers: Set<String> {
        Set(attachmentConfigurations.compactMap { $0?.bridgeInterfaceIdentifier })
    }

    var hasBridgedAttachments: Bool {
        !bridgeInterfaceIdentifiers.isEmpty
    }

    func changeBridgeInterface(to interfaceIdentifier: String) throws {
        guard VZBridgedNetworkInterface.networkInterfaces.contains(where: {
            $0.identifier == interfaceIdentifier
        }) else {
            throw Failure("The bridged network interface \(interfaceIdentifier.quoted) is not currently available.")
        }

        let bridgedDeviceIndices = attachmentConfigurations.indices.filter {
            attachmentConfigurations[$0]?.bridgeInterfaceIdentifier != nil
        }

        guard !bridgedDeviceIndices.isEmpty else {
            throw Failure("This virtual machine has no bridged network attachments.")
        }

        for deviceIndex in bridgedDeviceIndices {
            guard var configuration = attachmentConfigurations[deviceIndex] else { continue }

            configuration.kind = .bridge(interfaceIdentifier: interfaceIdentifier)
            attachmentConfigurations[deviceIndex] = configuration
        }

        stopMonitoringHostInterfaces()
        startMonitoringHostInterfaces()

        for deviceIndex in bridgedDeviceIndices {
            scheduleRecovery(
                forDeviceAt: deviceIndex,
                replacingCurrentAttachment: true,
                initialDelay: 0,
                reason: .bridgeInterfaceChanged
            )
        }

        logger.info("Changed \(bridgedDeviceIndices.count) bridged network device(s) to host interface \(interfaceIdentifier, privacy: .public)")
    }

    func attachmentWasDisconnected(
        in virtualMachine: VZVirtualMachine,
        networkDevice: VZNetworkDevice,
        error: Error
    ) {
        let nsError = error as NSError
        let attachmentDescription = String(describing: networkDevice.attachment)

        guard self.virtualMachine === virtualMachine else {
            logger.info("Ignoring network disconnection from a stale VM instance")
            return
        }

        guard let deviceIndex = virtualMachine.networkDevices.firstIndex(where: { $0 === networkDevice }) else {
            logger.error("A network attachment disconnected but its device is not part of the VM: domain=\(nsError.domain, privacy: .public) code=\(nsError.code) error=\(nsError.localizedDescription, privacy: .public) userInfo=\(String(describing: nsError.userInfo), privacy: .public) attachment=\(attachmentDescription, privacy: .public)")
            return
        }

        let macAddress = attachmentConfigurations.indices.contains(deviceIndex)
            ? attachmentConfigurations[deviceIndex]?.macAddress ?? "unknown"
            : "unknown"

        logger.error("Network attachment disconnected: device=\(deviceIndex) MAC=\(macAddress, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) error=\(nsError.localizedDescription, privacy: .public) userInfo=\(String(describing: nsError.userInfo), privacy: .public) attachment=\(attachmentDescription, privacy: .public)")

        guard attachmentConfigurations.indices.contains(deviceIndex),
              attachmentConfigurations[deviceIndex] != nil
        else {
            logger.error("No recovery configuration is available for network device \(deviceIndex)")
            return
        }

        guard recoveryTasks[deviceIndex] == nil else {
            logger.debug("Network recovery is already active for device \(deviceIndex)")
            return
        }

        scheduleRecovery(
            forDeviceAt: deviceIndex,
            replacingCurrentAttachment: false,
            initialDelay: Self.recoveryDelays[0],
            reason: .attachmentDisconnected
        )
    }

    fileprivate func dynamicStoreDidChange(_ changedKeys: [String]) {
        guard let store = dynamicStore else { return }

        for key in Set(changedKeys) {
            guard let interfaceIdentifier = interfaceIdentifierByLinkKey[key] else { continue }

            let wasActive = interfaceLinkStates[interfaceIdentifier]
            let isActive = Self.isLinkActive(interfaceIdentifier: interfaceIdentifier, store: store)
            interfaceLinkStates[interfaceIdentifier] = isActive

            logger.debug("Host bridge interface \(interfaceIdentifier, privacy: .public) link state changed: active=\(isActive)")

            guard wasActive == false, isActive else { continue }

            handleHostInterfaceBecameActive(interfaceIdentifier)
        }
    }

    private func handleHostInterfaceBecameActive(_ interfaceIdentifier: String) {
        let deviceIndices = attachmentConfigurations.indices.filter {
            attachmentConfigurations[$0]?.bridgeInterfaceIdentifier == interfaceIdentifier
        }

        guard !deviceIndices.isEmpty else { return }

        logger.info("Host bridge interface \(interfaceIdentifier, privacy: .public) became active; scheduling attachment replacement for \(deviceIndices.count) device(s)")

        for deviceIndex in deviceIndices {
            scheduleRecovery(
                forDeviceAt: deviceIndex,
                replacingCurrentAttachment: true,
                initialDelay: Self.hostInterfaceDebounceDelay,
                reason: .hostInterfaceBecameActive
            )
        }
    }

    private func scheduleRecovery(
        forDeviceAt deviceIndex: Int,
        replacingCurrentAttachment: Bool,
        initialDelay: TimeInterval,
        reason: RecoveryReason
    ) {
        guard virtualMachine.networkDevices.indices.contains(deviceIndex),
              attachmentConfigurations.indices.contains(deviceIndex),
              let attachmentConfiguration = attachmentConfigurations[deviceIndex]
        else {
            logger.error("Unable to schedule recovery for network device \(deviceIndex): recovery configuration is unavailable")
            return
        }

        if let existingTask = recoveryTasks.removeValue(forKey: deviceIndex) {
            existingTask.task.cancel()
        }

        let networkDevice = virtualMachine.networkDevices[deviceIndex]
        let taskID = UUID()

        let task = Task { @MainActor [weak self, weak virtualMachine, weak networkDevice] in
            var attempt = 0
            var shouldReplaceCurrentAttachment = replacingCurrentAttachment
            var nextDelay = initialDelay

            defer {
                self?.recoveryDidFinish(forDeviceAt: deviceIndex, taskID: taskID)
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(nextDelay))
                } catch {
                    return
                }

                guard let self, let virtualMachine, let networkDevice,
                      self.virtualMachine === virtualMachine
                else { return }

                if networkDevice.attachment != nil && !shouldReplaceCurrentAttachment {
                    self.logger.info("Network device \(deviceIndex) recovered before retry was necessary")
                    return
                }

                shouldReplaceCurrentAttachment = false
                attempt += 1

                self.logger.info("Attempting to reconnect network device \(deviceIndex) (\(attachmentConfiguration.description, privacy: .public), MAC=\(attachmentConfiguration.macAddress, privacy: .public), reason=\(reason.rawValue, privacy: .public), attempt=\(attempt))")

                do {
                    let newAttachment = try attachmentConfiguration.makeAttachment()
                    networkDevice.attachment = newAttachment

                    self.logger.debug("Assigned new attachment to network device \(deviceIndex): \(String(describing: newAttachment), privacy: .public)")

                    try await Task.sleep(for: .seconds(Self.attachmentStabilizationDelay))

                    guard self.virtualMachine === virtualMachine else { return }

                    if networkDevice.attachment != nil {
                        self.logger.info("Successfully reconnected network device \(deviceIndex) (\(attachmentConfiguration.description, privacy: .public), MAC=\(attachmentConfiguration.macAddress, privacy: .public))")
                        return
                    }

                    self.logger.error("Network device \(deviceIndex) rejected the replacement attachment; retrying")
                } catch is CancellationError {
                    return
                } catch {
                    self.logger.error("Failed to reconnect network device \(deviceIndex) on attempt \(attempt): \(error, privacy: .public)")
                }

                let delayIndex = min(attempt, Self.recoveryDelays.count - 1)
                nextDelay = Self.recoveryDelays[delayIndex]
            }
        }

        recoveryTasks[deviceIndex] = RecoveryTask(id: taskID, task: task)
    }

    private func recoveryDidFinish(forDeviceAt deviceIndex: Int, taskID: UUID) {
        guard recoveryTasks[deviceIndex]?.id == taskID else { return }

        recoveryTasks.removeValue(forKey: deviceIndex)
    }

    private func cancelRecoveryTasks() {
        recoveryTasks.values.forEach { $0.task.cancel() }
        recoveryTasks.removeAll()
    }

    private func stopMonitoringHostInterfaces() {
        if let dynamicStore {
            SCDynamicStoreSetDispatchQueue(dynamicStore, nil)
        }

        dynamicStore = nil
        interfaceIdentifierByLinkKey.removeAll()
        interfaceLinkStates.removeAll()
    }

    private static func linkStateKey(for interfaceIdentifier: String) -> String {
        SCDynamicStoreKeyCreateNetworkInterfaceEntity(
            nil,
            kSCDynamicStoreDomainState,
            interfaceIdentifier as CFString,
            kSCEntNetLink
        ) as String
    }

    private static func isLinkActive(
        interfaceIdentifier: String,
        store: SCDynamicStore
    ) -> Bool {
        let key = linkStateKey(for: interfaceIdentifier)

        guard let linkState = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else {
            return false
        }

        return linkState[kSCPropNetLinkActive as String] as? Bool == true
    }
}
