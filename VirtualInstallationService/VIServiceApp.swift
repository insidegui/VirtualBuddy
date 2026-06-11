import Cocoa
import OSLog
@_spi(VirtualInstallationService) import VirtualInstallation

final class VIServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let logger = Logger(subsystem: kVirtualInstallationSubsystem, category: String(describing: VIServiceDelegate.self))

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.debug("New connection: \(newConnection)")

        let service = VirtualInstallationService(clientConnection: newConnection)

        newConnection.setVirtualInstallationCodeSigningRequirement()

        newConnection.invalidationHandler = { [self, weak service] in
            logger.notice("Connection invalidated: \(newConnection)")
            service?.terminate(reason: "Connection invalidated")
        }

        newConnection.interruptionHandler = { [self, weak service] in
            logger.warning("Connection interrupted: \(newConnection)")
            service?.terminate(reason: "Connection interrupted")
        }

        newConnection.exportedInterface = NSXPCInterface(with: VirtualInstallationServiceProtocol.self)
        newConnection.exportedObject = service

        newConnection.remoteObjectInterface = NSXPCInterface(with: VirtualInstallationClientProtocol.self)

        newConnection.activate()

        return true
    }

    private lazy var listener = NSXPCListener.service()

    func bootstrap() {
        listener.delegate = self
        listener.activate()
    }
}

@main
struct VIServiceApp {
    private static let logger = Logger(subsystem: kVirtualInstallationSubsystem, category: String(describing: VIServiceApp.self))

    private static let delegate = VIServiceDelegate()

    static func main() {
        logger.log("Service main.")

        delegate.bootstrap()
    }
}
