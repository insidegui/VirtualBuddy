import Foundation
import OSLog
import Combine
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import Virtualization

/// Handles the underlying WebSocket client for VirtualBuddy.
public final class WHGuestClient: ObservableObject {

    private let logger = Logger(for: WHGuestClient.self)

    private enum Initializer {
        case virtualization(device: VZVirtioSocketDevice, port: UInt32)
        case fileDescriptor(fd: Int32)
    }

    private let initializer: Initializer
    private var invalidationHandler: (() -> Void)?

    public init(device: VZVirtioSocketDevice, port: UInt32) {
        self.initializer = .virtualization(device: device, port: port)
    }

    public init(fileDescriptor: Int32, invalidationHandler: (() -> Void)? = nil) {
        self.initializer = .fileDescriptor(fd: fileDescriptor)
        self.invalidationHandler = invalidationHandler
    }

    @MainActor
    @Published public private(set) var isConnected = false

    private var socketConnectionTask: Task<Void, Never>?
    private var socketConnection: VZVirtioSocketConnection?

    public func activate() {
        guard socketConnectionTask == nil else { return }

        logger.debug("Activating client")

        switch initializer {
        case .virtualization(let device, let port):
            runVirtualizationConnection(device: device, port: port)
        case .fileDescriptor(let fd):
            Task {
                do {
                    try await connect(using: fd)
                } catch {
                    logger.error("Connection failed: \(error, privacy: .public)")

                    invalidationHandler?()
                }
            }
        }
    }

    private func runVirtualizationConnection(device: VZVirtioSocketDevice, port: UInt32) {
        socketConnectionTask = Task {
            while !(await isConnected) {
                await Task.yield()

                try? await Task.sleep(nanoseconds: 5_000_000_000)

                guard !Task.isCancelled else { return }

                do {
                    logger.debug("Attempting connection...")

                    let connection = try await Task { @MainActor in try await device.connect(toPort: port) }.value

                    logger.debug("Connection socket opened")

                    self.socketConnection = connection

                    await MainActor.run { isConnected = true }

                    try await connect(using: connection.fileDescriptor)
                } catch {
                    logger.warning("Connection failed: \(error, privacy: .public)")

                    reset()
                }
            }
        }
    }

    private var guestConnection: WHGuestConnection? {
        didSet { bindConnection() }
    }

    private func connect(using fileDescriptor: Int32) async throws {
        let newConnection: WHGuestConnection

        if UserDefaults.standard.bool(forKey: "WHUseXPC") {
            guard case .virtualization = initializer else {
                preconditionFailure("WHUseXPC can't be used with file descriptor connection")
            }

            logger.info("Using XPC service to handle guest connection")

            newConnection = WHXPCGuestConnection()
        } else {
            logger.info("Using in-app service to handle guest connection")

            newConnection = WHInAppGuestConnection()
        }

        self.guestConnection = newConnection

        try await newConnection.connect(using: fileDescriptor) { [weak self] connection in
            guard let self else { return }
            guard let currentConnection = self.guestConnection else { return }
            guard connection === currentConnection else { return }

            logger.warning("Connection invalidated")

            self.invalidationHandler?()

            self.reset()
        }
    }

    private func reset() {
        Task {
            await MainActor.run { isConnected = false }

            self.socketConnectionTask?.cancel()
            self.socketConnectionTask = nil

            self.socketConnection?.close()
            self.socketConnection = nil

            guard case .virtualization = initializer else { return }

            try? await Task.sleep(nanoseconds: 1_000_000_000)

            activate()
        }
    }

    private var connectionCancellables = Set<AnyCancellable>()

    private func bindConnection() {
        connectionCancellables.removeAll()

        guard let guestConnection else { return }

        guestConnection.packets.sink { [weak self] packet in
            guard let self else { return }
            self.inboundPacketSubject.send(packet)
        }
        .store(in: &connectionCancellables)

        Task {
            let reverseBacklog = await MainActor.run {
                let result = backlog.reversed()
                backlog.removeAll()
                return result
            }

            for packet in reverseBacklog {
                do {
                    try await guestConnection.send(packet)
                } catch {
                    logger.warning("Backlog packet send failed: \(error, privacy: .public)")
                }
            }
        }
    }

    /// Produces a new element for each packet received from the connected client.
    var packets: AnyPublisher<WormholePacket, Never> { inboundPacketSubject.eraseToAnyPublisher() }
    private let inboundPacketSubject = PassthroughSubject<WormholePacket, Never>()

    @MainActor
    private var backlog = [WormholePacket]()

    func send(_ packet: WormholePacket) async throws {
        guard let guestConnection else {
            logger.debug("Adding \(packet.payloadType) to backlog for later")

            await MainActor.run { backlog.append(packet) }
            return
        }

        logger.debug("Sending \(packet.payloadType)")

        try await guestConnection.send(packet)
    }

}
