import Foundation
import Darwin
import OSLog

protocol LegacyClipboardConnection: Sendable {
    var pings: AsyncStream<Void> { get }
    var clipboards: AsyncStream<[LegacyClipboardItem]> { get }
    func write(_ data: Data) async throws
    func close()
    func waitUntilClosed() async
}

/// Dispatch sources and channels are thread-safe. The parser and input descriptor
/// are confined to `queue`; descriptors close only in their cleanup handlers.
/// No mutable state is accessed from the calling actor.
final class LegacyClipboardPipeConnection: LegacyClipboardConnection, @unchecked Sendable {
    let pings: AsyncStream<Void>
    let clipboards: AsyncStream<[LegacyClipboardItem]>
    private let reader: DispatchSourceRead
    private let writer: DispatchIO
    private let closed: DispatchGroup

    init(input: FileHandle, output: FileHandle) throws {
        let inputFD = dup(input.fileDescriptor)
        guard inputFD >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        let outputFD = dup(output.fileDescriptor)
        guard outputFD >= 0 else {
            Darwin.close(inputFD)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard fcntl(inputFD, F_SETFL, fcntl(inputFD, F_GETFL) | O_NONBLOCK) >= 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(inputFD)
            Darwin.close(outputFD)
            throw error
        }
        let queue = DispatchQueue(label: "VirtualBuddy.LegacyClipboard")
        let closed = DispatchGroup()
        self.closed = closed
        closed.enter()
        closed.enter()
        let (pings, pingOutput) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (clipboards, clipboardOutput) = AsyncStream<[LegacyClipboardItem]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.pings = pings
        self.clipboards = clipboards
        let reader = DispatchSource.makeReadSource(fileDescriptor: inputFD, queue: queue)
        self.reader = reader
        let writer = DispatchIO(type: .stream, fileDescriptor: outputFD, queue: queue) { _ in
            Darwin.close(outputFD)
            closed.leave()
        }
        self.writer = writer
        // This state is exclusively owned by the serial source's queue.
        let input = InputState()
        reader.setEventHandler {
            do {
                var bytes = [UInt8](repeating: 0, count: 64 * 1024)
                // Yield the queue regularly so cancellation cannot be starved.
                for _ in 0..<16 {
                    let count = Darwin.read(inputFD, &bytes, bytes.count)
                    if count < 0 {
                        if errno == EAGAIN { return }
                        if errno == EINTR { continue }
                        throw POSIXError(.init(rawValue: errno) ?? .EIO)
                    }
                    guard count > 0 else { reader.cancel(); writer.close(flags: .stop); return }
                    for event in try input.parser.append(Data(bytes.prefix(count))) {
                        switch event {
                        case .ping: pingOutput.yield(())
                        case .clipboard(let items): clipboardOutput.yield(items)
                        }
                    }
                }
            } catch {
                Logger(subsystem: "codes.rambo.VirtualCore", category: "LegacyClipboard")
                    .error("Legacy clipboard input failed: \(error.localizedDescription, privacy: .public)")
                reader.cancel()
                writer.close(flags: .stop)
            }
        }
        reader.setCancelHandler {
            Darwin.close(inputFD)
            pingOutput.finish()
            clipboardOutput.finish()
            closed.leave()
        }
        reader.resume()
    }

    func write(_ data: Data) async throws {
        let bytes = data.withUnsafeBytes { DispatchData(bytes: $0) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.write(offset: 0, data: bytes, queue: .global(qos: .utility)) { done, _, error in
                guard done else { return }
                if error == 0 { continuation.resume() }
                else { continuation.resume(throwing: POSIXError(.init(rawValue: error) ?? .EIO)) }
            }
        }
    }

    func close() {
        reader.cancel()
        writer.close(flags: .stop)
    }

    func waitUntilClosed() async {
        await withCheckedContinuation { continuation in
            closed.notify(queue: .global(qos: .utility)) { continuation.resume() }
        }
    }

    deinit { close() }

    private final class InputState {
        var parser = LegacyClipboardPacket()
    }
}
