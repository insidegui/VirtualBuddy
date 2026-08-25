import Foundation
import OSLog
import Virtualization
import VirtualWormhole

final class HostFileTransferServer: NSObject, VZVirtioSocketListenerDelegate {
    private let logger = Logger(for: HostFileTransferServer.self)
    private let listener = VZVirtioSocketListener()
    private let connectionLock = NSLock()
    private let transferLock = NSLock()

    private var connection: VZVirtioSocketConnection?

    override init() {
        super.init()
        listener.delegate = self
    }

    var isConnected: Bool {
        connectionLock.withLock {
            guard let connection else { return false }
            return connection.fileDescriptor >= 0
        }
    }

    func listen(on socketDevice: VZVirtioSocketDevice) {
        socketDevice.setSocketListener(listener, forPort: FileTransferProtocol.port)
    }

    func invalidate() {
        connectionLock.withLock {
            connection?.close()
            connection = nil
        }
    }

    func send(sessionID: UUID, sourceURLs: [URL]) async throws {
        try transferLock.withLock {
            let connection = try currentConnection()
            let handle = FileHandle(fileDescriptor: connection.fileDescriptor, closeOnDealloc: false)

            do {
                logger.notice(
                    "Host file drag \(sessionID, privacy: .public) transfer started with \(sourceURLs.count, privacy: .public) root item(s)"
                )
                try Self.writeTransfer(
                    sessionID: sessionID,
                    sourceURLs: sourceURLs,
                    to: handle
                )
                logger.notice("Host file drag \(sessionID, privacy: .public) transfer completed")
            } catch {
                logger.error(
                    "Host file drag \(sessionID, privacy: .public) transfer failed: \(error, privacy: .public)"
                )
                discard(connection)
                throw error
            }
        }
    }

    func listener(
        _ listener: VZVirtioSocketListener,
        shouldAcceptNewConnection connection: VZVirtioSocketConnection,
        from socketDevice: VZVirtioSocketDevice
    ) -> Bool {
        connectionLock.withLock {
            self.connection?.close()
            self.connection = connection
        }

        logger.notice("Guest file transfer connection is ready")
        return true
    }

    private func currentConnection() throws -> VZVirtioSocketConnection {
        try connectionLock.withLock {
            guard let connection, connection.fileDescriptor >= 0 else {
                throw CocoaError(
                    .serviceApplicationNotFound,
                    userInfo: [NSLocalizedDescriptionKey: "VirtualBuddyGuest is not ready to receive files."]
                )
            }
            return connection
        }
    }

    private func discard(_ failedConnection: VZVirtioSocketConnection) {
        connectionLock.withLock {
            guard connection === failedConnection else { return }
            connection?.close()
            connection = nil
        }
    }
}

private extension HostFileTransferServer {
    struct TransferSource {
        var url: URL
        var relativePath: String
        var entry: FileTransferEntry
    }

    static func writeTransfer(sessionID: UUID, sourceURLs: [URL], to handle: FileHandle) throws {
        guard !sourceURLs.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        var accessedURLs = [URL]()
        for url in sourceURLs where url.startAccessingSecurityScopedResource() {
            accessedURLs.append(url)
        }
        defer {
            accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        }

        let rootNames = uniqueRootNames(for: sourceURLs)
        let manifest = FileTransferManifest(sessionID: sessionID, rootPaths: rootNames)
        try FileTransferProtocol.writeFrame(manifest, to: handle)

        for (sourceURL, rootName) in zip(sourceURLs, rootNames) {
            for source in try transferSources(at: sourceURL, relativePath: rootName) {
                try Task.checkCancellation()
                try FileTransferProtocol.writeFrame(source.entry, to: handle)

                guard source.entry.kind == .regularFile else { continue }
                try writeFile(at: source.url, byteCount: source.entry.byteCount, to: handle)
            }
        }

        try FileTransferProtocol.writeEnd(to: handle)
    }

    static func transferSources(at url: URL, relativePath: String) throws -> [TransferSource] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let type = attributes[.type] as? FileAttributeType
        let permissions = (attributes[.posixPermissions] as? NSNumber).map { UInt16(truncating: $0) }
        let modificationDate = attributes[.modificationDate] as? Date

        switch type {
        case .typeDirectory:
            let directory = TransferSource(
                url: url,
                relativePath: relativePath,
                entry: FileTransferEntry(
                    relativePath: relativePath,
                    kind: .directory,
                    posixPermissions: permissions,
                    modificationDate: modificationDate
                )
            )

            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
            ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            return try children.reduce(into: [directory]) { result, child in
                let childPath = relativePath + "/" + child.lastPathComponent
                result.append(contentsOf: try transferSources(at: child, relativePath: childPath))
            }

        case .typeRegular:
            let byteCount = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            return [
                TransferSource(
                    url: url,
                    relativePath: relativePath,
                    entry: FileTransferEntry(
                        relativePath: relativePath,
                        kind: .regularFile,
                        byteCount: byteCount,
                        posixPermissions: permissions,
                        modificationDate: modificationDate
                    )
                )
            ]

        case .typeSymbolicLink:
            return [
                TransferSource(
                    url: url,
                    relativePath: relativePath,
                    entry: FileTransferEntry(
                        relativePath: relativePath,
                        kind: .symbolicLink,
                        posixPermissions: permissions,
                        modificationDate: modificationDate,
                        symbolicLinkDestination: try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                    )
                )
            ]

        default:
            throw CocoaError(
                .fileReadUnsupportedScheme,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported file type: \(url.lastPathComponent)"]
            )
        }
    }

    static func writeFile(at url: URL, byteCount: UInt64, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }

        var remaining = byteCount
        let chunkSize: UInt64 = 1_024 * 1_024

        while remaining > 0 {
            try Task.checkCancellation()

            let requestedCount = Int(min(remaining, chunkSize))
            guard let data = try input.read(upToCount: requestedCount), !data.isEmpty else {
                throw CocoaError(
                    .fileReadCorruptFile,
                    userInfo: [NSLocalizedDescriptionKey: "The source file changed while it was being transferred: \(url.lastPathComponent)"]
                )
            }

            try output.write(contentsOf: data)
            remaining -= UInt64(data.count)
        }
    }

    static func uniqueRootNames(for urls: [URL]) -> [String] {
        var usedNames = Set<String>()

        return urls.map { url in
            let originalName = url.lastPathComponent
            var candidate = originalName
            var suffix = 2

            while usedNames.contains(candidate) {
                candidate = duplicateName(for: originalName, suffix: suffix)
                suffix += 1
            }

            usedNames.insert(candidate)
            return candidate
        }
    }

    static func duplicateName(for name: String, suffix: Int) -> String {
        let url = URL(filePath: name)
        let pathExtension = url.pathExtension
        guard !pathExtension.isEmpty else { return "\(name) \(suffix)" }

        return "\(url.deletingPathExtension().lastPathComponent) \(suffix).\(pathExtension)"
    }
}
