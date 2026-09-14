//
//  DefaultsDomain+ExportImport.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 09/03/23.
//

import Cocoa
import OSLog

public extension DefaultsDomainDescriptor {

    func exportDefaults(to url: URL) async throws {
        try await runDefaults("export", domainName: id, plistPath: url.path)

        try postProcessPlist(at: url)
    }

    func importDefaults(from url: URL) async throws {
        try await runDefaults("import", domainName: id, plistPath: url.path)

        try await performRestartIfNeeded()
    }

    private func runDefaults(_ verb: String, domainName: String, plistPath: String) async throws {
        try await DefaultsCommand().run(executable: "/usr/bin/defaults", arguments: [verb, domainName, plistPath])
    }

    @MainActor
    func performRestartIfNeeded() async throws {
        try Task.checkCancellation()
        guard let restart else { return }
        
        guard target.isRunning else { return }
        
        if restart.needsConfirmation {
            let shouldRestart = await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Restart \(target.name)?"
                alert.informativeText = "To apply the new settings, \(target.name) must be restarted. Would you like to restart it now?"
                alert.addButton(withTitle: "Restart Now")
                alert.addButton(withTitle: "Later")

                return alert.runModal() == .alertFirstButtonReturn
            }

            guard shouldRestart else { return }
        }

        try await DefaultsCommand().run(executable: "/bin/sh", arguments: ["-c", restart.command])

        guard restart.shouldRelaunch, let url = target.bundleURL else { return }

        try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func postProcessPlist(at url: URL) throws {
        guard !ignoredKeyPaths.isEmpty else { return }

        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil)
        guard let dict = plist as? NSMutableDictionary else {
            throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "The exported defaults domain is not a valid property list."])
        }

        for key in ignoredKeyPaths {
            dict.setValue(nil, forKeyPath: key)
        }

        let updatedPlist = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)

        try updatedPlist.write(to: url)
    }

}

// A separate actor owns each subprocess. Output goes to files so a full pipe
// cannot deadlock a command, and suspension leaves cancellation free to run.
private actor DefaultsCommand {
    private var process: Process?

    func run(executable: String, arguments: [String]) async throws {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output")
        let errors = directory.appendingPathComponent("errors")
        try Data().write(to: output)
        try Data().write(to: errors)
        let outHandle = try FileHandle(forWritingTo: output)
        defer { try? outHandle.close() }
        let errHandle = try FileHandle(forWritingTo: errors)
        defer { try? errHandle.close() }
        let command = Process()
        command.executableURL = URL(fileURLWithPath: executable)
        command.arguments = arguments
        command.standardOutput = outHandle
        command.standardError = errHandle
        process = command
        defer { command.terminationHandler = nil; process = nil }
        let status: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                command.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
                do { try command.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
        try Task.checkCancellation()
        guard status == 0 else {
            let reason = String(decoding: try Data(contentsOf: errors).prefix(4096), as: UTF8.self)
            throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Defaults command failed (exit \(status)). \(reason)"])
        }
    }

    private func cancel() {
        if let process, process.isRunning { process.terminate() }
    }
}
