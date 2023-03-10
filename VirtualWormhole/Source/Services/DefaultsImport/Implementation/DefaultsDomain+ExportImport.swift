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
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = [
            verb,
            domainName,
            plistPath
        ]

        try proc.checkRun()
    }

    func performRestartIfNeeded() async throws {
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

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [
            "-c",
            restart.command
        ]
        try proc.checkRun()

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

extension Pipe {
    func readString() -> String? {
        guard let data = try? fileHandleForReading.readToEnd() else { return nil }
        guard !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

extension Process {

    private static let logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "Process")

    @discardableResult
    func checkRun(expectedStatus: Int32 = 0) throws -> Data? {
        let errPipe = Pipe()
        let outPipe = Pipe()
        standardError = errPipe
        standardOutput = outPipe

        try run()
        waitUntilExit()

        let errStr = errPipe.readString()

        guard terminationStatus == expectedStatus else {
            var info: [String: Any] = [
                NSLocalizedDescriptionKey: "Command failed with exit code \(terminationStatus)"
            ]
            if let errStr {
                Self.logger.error("Command \(self.executableURL?.lastPathComponent ?? "<nil>", privacy: .public) failed with exit code \(self.terminationStatus, privacy: .public): \(errStr, privacy: .public)")
                info[NSLocalizedFailureReasonErrorKey] = errStr
            }
            throw CocoaError(.coderReadCorrupt, userInfo: info)
        }

        return try? outPipe.fileHandleForReading.readToEnd()
    }

}
