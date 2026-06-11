import Foundation
import os

public final class RestoreLog: @unchecked Sendable {
    private let logger: Logger
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let name = "RestoreLog(\(fileURL.deletingPathExtension().lastPathComponent))"
        self.logger = Logger(subsystem: kVirtualInstallationSubsystem, category: name)
    }

    public func stream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let task = Task {
                let handle = try self.fileHandle

                guard !Task.isCancelled else { return }

                do {
                    for try await line in handle.bytes.lines {
                        continuation.yield(line)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func invalidate() {
        logger.debug(#function)

        _fileHandle.withLock {
            _ = try? $0?.close()
        }
    }

    private let _fileHandle = OSAllocatedUnfairLock<FileHandle?>(initialState: nil)
    private var fileHandle: FileHandle {
        get throws {
            try _fileHandle.withLock { handle in
                if let handle {
                    return handle
                } else {
                    let newHandle = try openFileHandle()

                    logger.info("Opened file handle at \(self.fileURL.path)")

                    handle = newHandle

                    return newHandle
                }
            }
        }
    }

    private func openFileHandle() throws -> FileHandle {
        do {
            if !fileURL.exists {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            
            return try FileHandle(forReadingFrom: fileURL)
        } catch {
            logger.error("Error opening file handle: \(error, privacy: .public)")

            throw error
        }
    }

    deinit { invalidate() }
}
