import Foundation
import Virtualization
import OSLog
import Combine
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

/// Connects from the host to a service running on VirtualBuddyGuest.
public final class WHGuestClient: ObservableObject {

    private let logger = Logger(for: WHGuestClient.self)

    private let device: VZVirtioSocketDevice
    private let port: UInt32

    public init(device: VZVirtioSocketDevice, port: UInt32) {
        self.device = device
        self.port = port
    }

    @MainActor
    @Published public private(set) var isConnected = false

    private var socketConnectionTask: Task<Void, Never>?
    private var socketConnection: VZVirtioSocketConnection?

    public func activate() {
        guard socketConnectionTask == nil else { return }

        logger.debug("Activating client")

        socketConnectionTask = Task {
            while !(await isConnected) {
                await Task.yield()

                try? await Task.sleep(nanoseconds: 5_000_000_000)

                guard !Task.isCancelled else { return }

                do {
                    logger.debug("Attempting connection...")

                    let connection = try await Task { @MainActor in try await device.connect(toPort: self.port) }.value

                    logger.debug("Connection socket opened")

                    self.socketConnection = connection

                    await MainActor.run { isConnected = true }

                    try await connect(using: connection)
                } catch {
                    logger.warning("Connection failed: \(error, privacy: .public)")

                    reset()
                }
            }
        }
    }

    private var guestConnection: WHGuestConnection?

    private func connect(using vmConnection: VZVirtioSocketConnection) async throws {
        let newConnection: WHGuestConnection

        if UserDefaults.standard.bool(forKey: "WHUseXPC") {
            logger.info("Using XPC service to handle guest connection")

            newConnection = WHXPCGuestConnection()
        } else {
            logger.info("Using in-app service to handle guest connection")

            newConnection = WHInAppGuestConnection()
        }

        self.guestConnection = newConnection

        try await newConnection.connect(using: vmConnection.fileDescriptor) { [weak self] connection in
            guard let self else { return }
            guard let currentConnection = self.guestConnection else { return }
            guard connection === currentConnection else { return }

            logger.warning("Connection invalidated")

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

            try? await Task.sleep(nanoseconds: 1_000_000_000)

            activate()
        }
    }

}
