import AppKit
import VirtualWormhole

/// The same signed executable has a small command-line installer mode. It runs
/// from a private copy, so neither the old nor replacement app executes while
/// its bundle is being moved.
enum GuestUpdateInstaller {
    static let helperArgument = "--virtualbuddy-install-update"
    static let receiptArgument = "--virtualbuddy-update-receipt"
    private static let directoryPrefix = ".VirtualBuddyGuest-Update-"

    @MainActor
    static func prepare(image: URL, package: GuestAppUpdatePackage) async throws -> PreparedGuestAppUpdate {
        guard !UserDefaults.standard.bool(forKey: "DisableInstall") else { throw GuestAppUpdateError.unsupported }
        let current = Bundle.main.bundleURL
        let directory = try await stage(image: image, package: package, current: current)
        let helper = directory.appendingPathComponent("Helper.app")
        guard let executable = Bundle(url: helper)?.executableURL else {
            try? FileManager.default.removeItem(at: directory)
            throw GuestAppUpdateError.invalidPackage
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = [helperArgument, String(ProcessInfo.processInfo.processIdentifier)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return PreparedGuestAppUpdate(launchInstaller: {
            try process.run()
            let ready = directory.appendingPathComponent("Ready")
            for _ in 0..<100 {
                try Task.checkCancellation()
                guard process.isRunning else { throw GuestAppUpdateError.invalidPackage }
                if FileManager.default.fileExists(atPath: ready.path) { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw GuestAppUpdateError.interrupted
        }, terminateApp: {
            NSApplication.shared.terminate(nil)
        }, discard: {
            if process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(at: directory)
        })
    }

    private static func stage(image: URL, package: GuestAppUpdatePackage, current: URL) async throws -> URL {
        let parent = current.deletingLastPathComponent().standardizedFileURL
        guard validApplicationsDirectory(parent), current.lastPathComponent == "VirtualBuddyGuest.app" else {
            throw GuestAppUpdateError.unsupported
        }
        let manager = FileManager.default
        let directory = parent.appendingPathComponent(directoryPrefix + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let mount = directory.appendingPathComponent("Image", isDirectory: true)
        try manager.createDirectory(at: mount, withIntermediateDirectories: false)
        do {
            try await GuestUpdateCommand().run("/usr/bin/hdiutil", [
                "attach", image.path, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path
            ])
            do {
                let source = mount.appendingPathComponent("VirtualBuddyGuest.app")
                try GuestUpdateFiles.validateApplication(at: source, replacing: current, expected: package.identity)
                let replacement = directory.appendingPathComponent("Replacement.app")
                try manager.copyItem(at: source, to: replacement)
                try GuestUpdateFiles.validateApplication(at: replacement, replacing: current, expected: package.identity)
                // Keep a separate executable bundle alive throughout replacement and rollback.
                try manager.copyItem(at: source, to: directory.appendingPathComponent("Helper.app"))
                try JSONEncoder().encode(package.identity).write(to: directory.appendingPathComponent("Identity.json"), options: .atomic)
                try Task.checkCancellation()
            } catch {
                await detach(mount)
                throw error
            }
            await detach(mount)
            try Task.checkCancellation()
            return directory
        } catch {
            // An interrupted attach may have mounted the volume before exiting.
            await detach(mount)
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    private static func detach(_ mount: URL) async {
        // Cleanup must run even if the transfer's task was cancelled.
        let cleanup = Task { try? await GuestUpdateCommand().run("/usr/bin/hdiutil", ["detach", mount.path]) }
        await cleanup.value
    }

    private static func validApplicationsDirectory(_ directory: URL) -> Bool {
        [URL(fileURLWithPath: "/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            .contains(directory.standardizedFileURL)
    }

    /// Invoked before AppKit startup, in the separate installer process only.
    static func runHelperIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard args.dropFirst().first == helperArgument else { return false }
        do {
            guard args.count == 3, let pid = Int32(args[2]), pid > 1, pid != getpid() else {
                throw GuestAppUpdateError.invalidPackage
            }
            try installAfterExit(pid: pid)
        } catch {
            NSLog("VirtualBuddyGuest updater: %@", error.localizedDescription)
        }
        return true
    }

    private static func installAfterExit(pid: pid_t) throws {
        let manager = FileManager.default
        let directory = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL
        guard directory.lastPathComponent.hasPrefix(directoryPrefix),
              UUID(uuidString: String(directory.lastPathComponent.dropFirst(directoryPrefix.count))) != nil,
              validApplicationsDirectory(directory.deletingLastPathComponent()) else {
            throw GuestAppUpdateError.invalidPackage
        }
        let destination = directory.deletingLastPathComponent().appendingPathComponent("VirtualBuddyGuest.app")
        let replacement = directory.appendingPathComponent("Replacement.app")
        let receipt = directory.appendingPathComponent("Launched")
        let identity = try JSONDecoder().decode(GuestAppIdentity.self, from: Data(contentsOf: directory.appendingPathComponent("Identity.json")))
        try GuestUpdateFiles.validateApplication(at: replacement, replacing: destination, expected: identity)
        try Data().write(to: directory.appendingPathComponent("Ready"), options: .atomic)

        // The helper has no AppKit event loop. Bounded polling also handles the
        // parent exiting before the helper starts observing it.
        guard wait(until: { kill(pid, 0) != 0 && errno == ESRCH }, seconds: 60) else {
            try? manager.removeItem(at: directory)
            throw GuestAppUpdateError.interrupted
        }
        try GuestUpdateFiles.validateApplication(at: replacement, replacing: destination, expected: identity)
        guard let currentBundle = Bundle(url: destination),
              let replacementBundle = Bundle(url: replacement),
              let relativeExecutable = replacementBundle.executableURL?.lastPathComponent,
              currentBundle.bundleIdentifier == replacementBundle.bundleIdentifier else { throw GuestAppUpdateError.invalidPackage }

        var exchanged = false
        var launched: Process?
        do {
            try GuestUpdateFiles.exchangeApplications(replacement, destination)
            exchanged = true
            let app = Process()
            app.executableURL = destination.appendingPathComponent("Contents/MacOS").appendingPathComponent(relativeExecutable)
            app.arguments = [receiptArgument, receipt.path]
            app.standardInput = FileHandle.nullDevice
            app.standardOutput = FileHandle.nullDevice
            app.standardError = FileHandle.nullDevice
            try app.run()
            launched = app
            let acknowledged = wait(until: { manager.fileExists(atPath: receipt.path) || !app.isRunning }, seconds: 60)
            guard acknowledged, manager.fileExists(atPath: receipt.path), app.isRunning else {
                throw GuestAppUpdateError.confirmationTimedOut
            }
            // Retain the previous app until startup and host reconnection are confirmed.
            try? manager.removeItem(at: directory)
        } catch {
            if let launched, launched.isRunning {
                launched.terminate()
                if !wait(until: { !launched.isRunning }, seconds: 10) {
                    kill(launched.processIdentifier, SIGKILL)
                    launched.waitUntilExit()
                }
            }
            // Keep a failed replacement for diagnosis; never delete the only good app.
            if exchanged { try GuestUpdateFiles.exchangeApplications(replacement, destination) }
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = [destination.path]
            try open.run()
            throw error
        }
    }

    private static func wait(until predicate: () -> Bool, seconds: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        repeat {
            if predicate() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return predicate()
    }

    @MainActor
    static func acknowledgeLaunch(whenConnected: () -> Bool) async {
        let args = CommandLine.arguments
        guard args.count == 3, args[1] == receiptArgument else { return }
        let receipt = URL(fileURLWithPath: args[2]).standardizedFileURL
        guard receipt.lastPathComponent == "Launched",
              receipt.deletingLastPathComponent().lastPathComponent.hasPrefix(directoryPrefix),
              receipt.deletingLastPathComponent().deletingLastPathComponent() == Bundle.main.bundleURL.deletingLastPathComponent() else { return }
        for _ in 0..<300 {
            guard !Task.isCancelled else { return }
            if whenConnected() {
                try? Data().write(to: receipt, options: .atomic)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
