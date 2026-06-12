import Foundation
import OSLog

public struct LogEntry: Identifiable, Hashable, Codable, CustomStringConvertible {
    public enum Level: String, Codable {
        case debug = "Debug"
        case trace = "Trace"
        case notice = "Notice"
        case info = "Info"
        case `default` = "Default"
        case warning = "Warning"
        case error = "Error"
        case fault = "Fault"
        case critical = "Critical"
    }

    public var id = UUID()
    public var date: Date = .now
    public var level: Level { _level ?? .default }
    public let traceID: UInt64
    public let message: String

    private var _level: Level? = nil

    public enum CodingKeys: String, CodingKey {
        case traceID = "traceID"
        case message = "eventMessage"
        case _level = "messageType"
    }
}

public extension LogEntry {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.sss"
        return f
    }()

    var formattedTime: String { Self.timeFormatter.string(from: date) }

    var description: String {
        "[\(formattedTime)] (\(level.rawValue)) - \(message)"
    }
}

public final class LogStreamer: ObservableObject {

    private let logger = Logger(for: LogStreamer.self)

    private var recoveryProcess: Process?
    private var logProcess: Process?

    @Published public private(set) var events = [LogEntry]()

    public enum Predicate: CustomStringConvertible {
        case library(String)
        case subsystem(String)
        case process(String)
        case custom(String)

        public var description: String {
            switch self {
            case .library(let name):
                return "senderImagePath contains '\(name)'"
            case .subsystem(let name):
                return "subsystem = '\(name)'"
            case .process(let name):
                return "process = '\(name)'"
            case .custom(let str):
                return str
            }
        }
    }

    public let predicate: Predicate
    public let startTime: Date

    public init(predicate: Predicate, startTime: Date = .now) {
        self.predicate = predicate
        self.startTime = startTime
    }

    public func activate() {
        logger.debug(#function)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = [
            "stream",
            "--level",
            "debug",
            "--style",
            "ndjson",
            "--predicate",
            "\(predicate)"
        ]

        let outPipe = Pipe()
        p.standardError = Pipe()
        p.standardOutput = outPipe

        do {
            try p.run()

            self.logProcess = p

            startStreaming(with: outPipe.fileHandleForReading)
        } catch {
            logger.fault("Failed to launch log process: \(String(describing: error), privacy: .public)")
        }
    }

    private func recoverLogMessagesIfNeeded() async {
        let secondsSinceStart = Date.now.timeIntervalSince(startTime)

        /// No need to recover if we've just started.
        guard secondsSinceStart >= 1.0 else { return }

        /// Only recover previous log messages if start time is not way too long ago (over 30 minutes).
        guard secondsSinceStart < 60 * 30 else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = [
            "show",
            "--debug",
            "--last",
            String(format: "%.0fs", secondsSinceStart),
            "--style",
            "ndjson",
            "--predicate",
            "\(predicate)"
        ]

        let outPipe = Pipe()
        p.standardError = Pipe()
        p.standardOutput = outPipe
        recoveryProcess = p

        defer { recoveryProcess = nil }

        do {
            try p.run()

            /// Recover entries by getting all of them and injecting directly into our events to bypass throttling.
            var recoveredEntries = [LogEntry]()
            for try await line in outPipe.fileHandleForReading.bytes.lines {
                guard let entry = try? decoder.decode(LogEntry.self, from: Data(line.utf8)) else { continue }
                recoveredEntries.append(entry)
            }
            self.events = recoveredEntries
        } catch {
            logger.error("Error recovering logs: \(error, privacy: .public)")
        }
    }

    private var streamTask: Task<Void, Never>?

    private func startStreaming(with fileHandle: FileHandle) {
        streamTask = Task { [weak self] in
            await self?.recoverLogMessagesIfNeeded()

            do {
                for try await line in fileHandle.bytes.lines {
                    await self?.onTaskProduceEvent(for: line)
                }
            } catch {
                self?.logger.error("AsyncSequence error: \(String(describing: error), privacy: .public)")
            }
        }

    }

    private let decoder = JSONDecoder()

    private func onTaskProduceEvent(for line: String) async {
        guard !line.contains("Filtering the log data using") else { return }

        do {
            let entry = try decoder.decode(LogEntry.self, from: Data(line.utf8))

            await MainActor.run { [weak self] in
                self?.events.append(entry)
            }
        } catch {
            logger.error("Error decoding log entry \(line, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    public func invalidate() {
        logger.debug(#function)

        streamTask?.cancel()
        streamTask = nil

        logProcess?.terminate()
        logProcess = nil
    }

    deinit { invalidate() }

}

#if DEBUG
public extension LogStreamer {
    static let previewSubsystemName = "codes.rambo.LogStreamer.PreviewSubsystem"
    static let previewLogger = Logger(subsystem: previewSubsystemName, category: previewSubsystemName)
    static var preview: LogStreamer {
        DispatchQueue.main.async {
            LogStreamer.previewLogger.debug("This is a debug message")
            LogStreamer.previewLogger.info("This is an info message")
            LogStreamer.previewLogger.notice("This is a notice message")
            LogStreamer.previewLogger.trace("This is a trace message")
            LogStreamer.previewLogger.log("This is a log message")
            LogStreamer.previewLogger.warning("This is a warning message")
            LogStreamer.previewLogger.error("This is an error message")
            LogStreamer.previewLogger.fault("This is a fault message")
            LogStreamer.previewLogger.critical("This is a critical message")
        }
        return LogStreamer(predicate: .subsystem(Self.previewSubsystemName))
    }
}

#endif
