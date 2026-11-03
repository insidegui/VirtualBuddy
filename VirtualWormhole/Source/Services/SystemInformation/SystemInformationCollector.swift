import AppKit
import Darwin
import SystemConfiguration

enum SystemInformationCollector {
    static func collect() async throws -> GuestSystemInformation {
        try Task.checkCancellation()
        let sipDescription = await SIPStatusReader().read()
        try Task.checkCancellation()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        var bootTime = timeval()
        var size = MemoryLayout.size(ofValue: bootTime)
        let bootDate = sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0
            ? Date(timeIntervalSince1970: Double(bootTime.tv_sec)) : nil
        return GuestSystemInformation(
            osVersion: versionString,
            osBuild: sysctlString("kern.osversion"),
            kernelVersion: sysctlString("kern.osrelease"),
            computerName: SCDynamicStoreCopyComputerName(nil, nil) as String?,
            architecture: sysctlString("hw.machine"),
            processorCount: ProcessInfo.processInfo.processorCount,
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            bootDate: bootDate,
            guestAppVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            guestAppBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            sipDescription: sipDescription
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 4096 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }

    @MainActor
    static func observeChanges(_ receive: @escaping @MainActor () -> Void) -> () -> Void {
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.willSleepNotification, NSWorkspace.willPowerOffNotification
        ]
        let observers = workspaceNames.map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { receive() }
            }
        }
        let appObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { receive() } }
        return {
            observers.forEach { workspace.removeObserver($0) }
            NotificationCenter.default.removeObserver(appObserver)
        }
    }
}

/// Each read owns its subprocess. Cancellation and a deadline both kill the
/// read-only command, so collecting metadata cannot hold up guest termination.
private actor SIPStatusReader {
    private enum ReadError: Error { case timedOut, unsuccessfulExit(Int32) }
    private var process: Process?

    func read() async -> String? {
        try? await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.run() }
            group.addTask {
                try await Task.sleep(for: .seconds(1))
                throw ReadError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()
        }
    }

    private func run() async throws -> String {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("status")
        try Data().write(to: output)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        command.arguments = ["status"]
        command.environment = ["LC_ALL": "C", "LANG": "C"]
        command.standardOutput = handle
        command.standardError = FileHandle.nullDevice
        process = command
        defer { command.terminationHandler = nil; process = nil }
        let status: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                command.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try command.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
        try Task.checkCancellation()
        guard status == 0 else { throw ReadError.unsuccessfulExit(status) }
        let reader = try FileHandle(forReadingFrom: output)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 8192) ?? Data()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cancel() {
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
