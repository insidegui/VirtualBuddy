import Darwin
import Foundation
import OSLog
import VirtualWormhole

struct StagedFileTransfer: Sendable {
    var sessionID: UUID
    var fileURLs: [URL]
    var directoryURL: URL
}

final class GuestFileTransferReceiver {
    typealias ReceiveHandler = @MainActor @Sendable (StagedFileTransfer) -> Void

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Guest", category: "FileTransferReceiver")
    private let receiveHandler: ReceiveHandler
    private var receiveTask: Task<Void, Never>?

    init(receiveHandler: @escaping ReceiveHandler) {
        self.receiveHandler = receiveHandler
    }

    func activate() {
        guard receiveTask == nil else { return }

        receiveTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.receiveContinuously()
        }
    }

    func invalidate() {
        receiveTask?.cancel()
        receiveTask = nil
    }

    private func receiveContinuously() async {
        while !Task.isCancelled {
            do {
                let handle = try openConnection()
                logger.notice("Connected to the host file transfer service")

                do {
                    while !Task.isCancelled {
                        let transfer = try receiveTransfer(from: handle)
                        await receiveHandler(transfer)
                    }
                } catch {
                    try? handle.close()
                    throw error
                }
            } catch is CancellationError {
                return
            } catch {
                logger.error("File transfer connection failed: \(error, privacy: .public)")
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func openConnection() throws -> FileHandle {
        let descriptor = socket(AF_VSOCK, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var noSigPipe: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout.size(ofValue: noSigPipe))
        )

        var address = sockaddr_vm()
        address.svm_len = UInt8(MemoryLayout<sockaddr_vm>.size)
        address.svm_family = sa_family_t(AF_VSOCK)
        address.svm_port = FileTransferProtocol.port
        address.svm_cid = UInt32(VMADDR_CID_HOST)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_vm>.size))
            }
        }

        guard result == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .ECONNREFUSED)
            Darwin.close(descriptor)
            throw error
        }

        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func receiveTransfer(from handle: FileHandle) throws -> StagedFileTransfer {
        guard let manifest = try FileTransferProtocol.readFrame(FileTransferManifest.self, from: handle) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard manifest.version == FileTransferProtocol.version else {
            throw CocoaError(
                .fileReadUnsupportedScheme,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported file transfer version: \(manifest.version)"]
            )
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "VirtualBuddyFileDrops", directoryHint: .isDirectory)
            .appending(path: manifest.sessionID.uuidString, directoryHint: .isDirectory)

        try? FileManager.default.removeItem(at: directoryURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        do {
            var attributesToApply = [(url: URL, attributes: [FileAttributeKey: Any])]()

            while let entry = try FileTransferProtocol.readFrame(FileTransferEntry.self, from: handle) {
                try Task.checkCancellation()

                let destinationURL = try FileTransferPath.destination(
                    for: entry.relativePath,
                    under: directoryURL
                )

                try create(entry, at: destinationURL, readingFrom: handle)

                if entry.kind != .symbolicLink {
                    var attributes = [FileAttributeKey: Any]()
                    if let permissions = entry.posixPermissions {
                        attributes[.posixPermissions] = NSNumber(value: permissions)
                    }
                    if let modificationDate = entry.modificationDate {
                        attributes[.modificationDate] = modificationDate
                    }
                    if !attributes.isEmpty {
                        attributesToApply.append((destinationURL, attributes))
                    }
                }
            }

            for item in attributesToApply.reversed() {
                try FileManager.default.setAttributes(item.attributes, ofItemAtPath: item.url.path)
            }

            let fileURLs = try manifest.rootPaths.map {
                try FileTransferPath.destination(for: $0, under: directoryURL)
            }

            return StagedFileTransfer(
                sessionID: manifest.sessionID,
                fileURLs: fileURLs,
                directoryURL: directoryURL
            )
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }

    private func create(_ entry: FileTransferEntry, at destinationURL: URL, readingFrom handle: FileHandle) throws {
        switch entry.kind {
        case .directory:
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        case .regularFile:
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }

            let output = try FileHandle(forWritingTo: destinationURL)
            defer { try? output.close() }

            var remaining = entry.byteCount
            let chunkSize: UInt64 = 1_024 * 1_024

            while remaining > 0 {
                try Task.checkCancellation()

                let data = try FileTransferProtocol.readExactly(Int(min(remaining, chunkSize)), from: handle)
                try output.write(contentsOf: data)
                remaining -= UInt64(data.count)
            }

        case .symbolicLink:
            guard let symbolicLinkDestination = entry.symbolicLinkDestination else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                atPath: destinationURL.path,
                withDestinationPath: symbolicLinkDestination
            )
        }
    }
}
