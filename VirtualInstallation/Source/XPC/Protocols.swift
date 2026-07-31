import Foundation

@objc(VirtualInstallationServiceProtocol)
public protocol VirtualInstallationServiceProtocol {
    func startVirtualMachineInstallation(
        ecid: ECID,
        restoreBundleURL: URL,
        simulateFailure: Bool,
        reply: @escaping @Sendable (_ error: Error?) -> ()
    )
    func cancelVirtualMachineInstallation(ecid: ECID, reply: @escaping @Sendable (_ error: Error?) -> ())
}

@objc(VirtualInstallationClientProtocol)
public protocol VirtualInstallationClientProtocol {
    func virtualMachineInstallationStateChanged(state: Data)
}
