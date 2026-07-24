import Foundation
import os

public final class RestoreLog: @unchecked Sendable {
    private static let maximumErrorSearchLength: UInt64 = 4 * 1_024 * 1_024

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

    func mostRecentRestoreError() -> NSError? {
        do {
            let contents = try tailContents(maximumLength: Self.maximumErrorSearchLength)
            return Self.mostRecentRestoreError(in: contents)
        } catch {
            logger.error("Failed to read restore log while looking for an error: \(error, privacy: .public)")
            return nil
        }
    }

    static func mostRecentRestoreError(in contents: String) -> NSError? {
        let domainPrefix = "CFError domain:"
        let codePrefix = " code:"
        let descriptionPrefix = " description:"

        for line in contents.components(separatedBy: .newlines).reversed() {
            guard let domainPrefixRange = line.range(of: domainPrefix) else { continue }

            let domainStart = domainPrefixRange.upperBound
            guard let codePrefixRange = line.range(
                of: codePrefix,
                range: domainStart..<line.endIndex
            ) else { continue }

            let codeStart = codePrefixRange.upperBound
            guard let descriptionPrefixRange = line.range(
                of: descriptionPrefix,
                range: codeStart..<line.endIndex
            ) else { continue }

            let domain = line[domainStart..<codePrefixRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let codeString = line[codeStart..<descriptionPrefixRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let description = line[descriptionPrefixRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)

            guard !domain.isEmpty, let code = Int(codeString), !description.isEmpty else { continue }

            return NSError(
                domain: domain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }

        return nil
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

    private func tailContents(maximumLength: UInt64) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let endOffset = try handle.seekToEnd()
        let startOffset = endOffset > maximumLength ? endOffset - maximumLength : 0
        try handle.seek(toOffset: startOffset)

        let data = try handle.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    deinit { invalidate() }
}
