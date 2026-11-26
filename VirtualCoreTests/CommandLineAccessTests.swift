import Foundation
import ManagedPreferencesKit
import Testing
import VirtualWormhole
@testable import VirtualCore

private struct PolicyStore: ManagedPreferenceStore {
    var values: [String: Any]
    func value(forKey key: String, domain: String) -> Any? { values[key] }
    func valueIsForced(forKey key: String, domain: String) -> Bool { values[key] != nil }
}

private func preferences(_ values: [String: Any] = [:]) -> VirtualBuddyManagedPreferences.Reader {
    VirtualBuddyManagedPreferences.schema.reader(store: PolicyStore(values: values))
}

@MainActor
struct CommandLineAccessTests {
    @Test func accessIsOffUnlessTheChoiceWasReadBackIntact() throws {
        let storage = SecuritySettingsStorage.inMemory()
        #expect(!storage.isCommandLineAccessEnabled())

        try storage.setCommandLineAccessEnabled(true)
        #expect(storage.isCommandLineAccessEnabled())

        try storage.setCommandLineAccessEnabled(false)
        #expect(!storage.isCommandLineAccessEnabled())

        var invalid = SecuritySettingsStorage.inMemory()
        invalid.savedCommandLineAccess = { Data("yes".utf8) }
        #expect(!invalid.isCommandLineAccessEnabled())

        var failing = SecuritySettingsStorage.inMemory()
        failing.savedCommandLineAccess = { throw Failure("The Keychain is locked.") }
        #expect(!failing.isCommandLineAccessEnabled())
    }

    @Test func organizationKeepsAccessOffWithoutChangingTheChoice() throws {
        let storage = SecuritySettingsStorage.inMemory()
        try storage.setCommandLineAccessEnabled(true)

        #expect(CommandLineAccess.isEnabled(storage: storage, preferences: preferences()))
        #expect(!CommandLineAccess.isEnabled(storage: storage, preferences: preferences(["DisableCommandLineAccess": true])))
        #expect(storage.isCommandLineAccessEnabled())
        #expect(!CommandLineAccess.isEnabled(storage: .inMemory(), preferences: preferences(["DisableCommandLineAccess": false])))
    }

    @Test func accessOnlyChangesWhileSecuritySettingsAreUnlockedAndObserversHearAboutIt() async throws {
        let storage = SecuritySettingsStorage.inMemory()
        let session = SecuritySettingsSession(storage: storage) { _ in }
        let monitor = CommandLineAccessMonitor(session: session, preferences: preferences()) {
            CommandLineAccess.isEnabled(storage: storage, preferences: preferences())
        }
        var changes = [Bool]()
        monitor.onChange = { changes.append($0) }

        #expect(!session.isCommandLineAccessEnabled)
        #expect(throws: Failure.self) { try session.setCommandLineAccessEnabled(true) }
        #expect(!storage.isCommandLineAccessEnabled())
        #expect(!monitor.isEnabled)

        try await session.unlock()
        try session.setCommandLineAccessEnabled(true)
        #expect(session.isCommandLineAccessEnabled)
        #expect(monitor.isEnabled)

        // Other security settings changing isn't a change to this one.
        try session.setTunnelLevel(.reviewNew)
        try session.setCommandLineAccessEnabled(false)
        #expect(changes == [true, false])
    }
}

struct CommandLineToolInstallerTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("vbctl-installer-\(UUID().uuidString)")
    private let suiteName = "CommandLineToolInstallerTests.\(UUID().uuidString)"

    private func tool(in app: String = "VirtualBuddy") -> URL {
        root.appendingPathComponent("\(app).app/Contents/MacOS/vbctl")
    }

    private func directory(_ name: String, create: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(name)
        if create { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return url
    }

    private func installer(tool: URL? = nil, candidates: [URL], path: [URL]) -> CommandLineToolInstaller {
        let suiteName = suiteName
        let path = path.map(\.path)
        return CommandLineToolInstaller(
            toolURL: tool ?? self.tool(),
            candidates: candidates,
            searchPath: { path },
            defaults: { UserDefaults(suiteName: suiteName)! }
        )
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func destination(of link: URL) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    }

    @Test func linksIntoTheFirstCandidateThatIsInThePathAndWritable() async throws {
        defer { cleanUp() }
        let notInPath = try directory("not-in-path")
        let readOnly = try directory("read-only")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path) }
        let usable = try directory("usable")
        let later = try directory("later")

        let installer = installer(candidates: [notInPath, readOnly, usable, later], path: [readOnly, usable, later])
        #expect(installer.status() == .notInstalled)

        let link = try await installer.install()
        #expect(link == usable.appendingPathComponent("vbctl"))
        #expect(destination(of: link) == tool().path)
        #expect(installer.status() == .installed(link))
        #expect(destination(of: notInPath.appendingPathComponent("vbctl")) == nil)
        #expect(destination(of: later.appendingPathComponent("vbctl")) == nil)

        installer.uninstall()
        #expect(destination(of: link) == nil)
        #expect(installer.status() == .notInstalled)
    }

    @Test func neverReplacesSomethingItDidNotCreate() async throws {
        defer { cleanUp() }
        let taken = try directory("taken")
        let foreign = taken.appendingPathComponent("vbctl")
        try Data("#!/bin/sh\n".utf8).write(to: foreign)
        let linked = try directory("linked")
        let elsewhere = linked.appendingPathComponent("vbctl")
        try FileManager.default.createSymbolicLink(atPath: elsewhere.path, withDestinationPath: "/usr/bin/true")

        let onlyTaken = installer(candidates: [taken, linked], path: [taken, linked])
        await #expect(throws: CommandLineToolInstaller.ManualInstallationRequired.self) { try await onlyTaken.install() }
        #expect(try Data(contentsOf: foreign) == Data("#!/bin/sh\n".utf8))
        #expect(destination(of: elsewhere) == "/usr/bin/true")
        #expect(onlyTaken.status() == .notInstalled)

        let free = try directory("free")
        let link = try await installer(candidates: [taken, linked, free], path: [taken, linked, free]).install()
        #expect(link == free.appendingPathComponent("vbctl"))
    }

    @Test func offersACommandWhenNoFolderCanBeWrittenTo() async throws {
        defer { cleanUp() }
        let unlisted = try directory("unlisted")
        let installer = installer(tool: root.appendingPathComponent("It's Here/VirtualBuddy.app/Contents/MacOS/vbctl"), candidates: [unlisted], path: [])

        do {
            try await installer.install()
            Issue.record("Installing should need the user's help" as Comment)
        } catch let error as CommandLineToolInstaller.ManualInstallationRequired {
            #expect(error.command.hasPrefix("sudo mkdir -p /usr/local/bin && sudo ln -sf '"))
            #expect(error.command.contains("It'\\''s Here/VirtualBuddy.app/Contents/MacOS/vbctl' /usr/local/bin/vbctl"))
        }
    }

    @Test func followsTheAppWhenItMovesAndReplacesItsOwnLinks() async throws {
        defer { cleanUp() }
        let bin = try directory("bin")
        let original = installer(candidates: [bin], path: [bin])
        let link = try await original.install()

        let moved = installer(tool: tool(in: "Applications/VirtualBuddy"), candidates: [bin], path: [bin])
        #expect(moved.status() == .notInstalled)
        moved.repairIfNeeded()
        #expect(destination(of: link) == tool(in: "Applications/VirtualBuddy").path)
        #expect(moved.status() == .installed(link))

        // A link left by another copy of the app is this installer's to replace.
        let other = installer(tool: tool(in: "VirtualBuddy-Dev"), candidates: [bin], path: [bin])
        #expect(try await other.install() == link)
        #expect(destination(of: link) == tool(in: "VirtualBuddy-Dev").path)
    }

    @Test func createsMissingFoldersOnlyInsideTheHomeFolder() async throws {
        defer { cleanUp() }
        let missing = try directory("missing", create: false)
        let installer = installer(candidates: [missing], path: [missing])
        await #expect(throws: CommandLineToolInstaller.ManualInstallationRequired.self) { try await installer.install() }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}

/// The ways the command-line tool changes service tunnels, none of which may approve what the user hasn't reviewed.
struct UnreviewedServiceTunnelChangeTests {
    private final class HostApprovals: @unchecked Sendable {
        private var digests: [String: Data] = [:]
        var store: SettingApprovals {
            SettingApprovals(digest: { self.digests[$0] }, record: { self.digests[$1] = $0 })
        }
    }

    private final class ChosenLevel: @unchecked Sendable {
        var value: ServiceTunnelSecurityLevel = .reviewAll
    }

    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let host = HostApprovals()
    private let storage = SecuritySettingsStorage.inMemory()
    private let level = ChosenLevel()
    private let web = ServiceTunnel(listensOnHost: true, listener: .tcp(8080), destination: .tcp(80))
    private let database = ServiceTunnel(listensOnHost: false, listener: .tcp(5432), destination: .tcp(5432))

    private var setting: ApprovedVMSetting<[ServiceTunnel]> { VBVirtualMachine.tunnelSetting(approvals: host.store) }

    private var security: ServiceTunnelSecurity {
        let level = level
        let storage = storage
        return ServiceTunnelSecurity(
            level: { level.value },
            isRemembered: { (try? storage.isRemembered($0)) ?? false },
            remember: { try storage.remember($0) }
        )
    }

    private func withVM(_ body: (VBVirtualMachine) throws -> Void) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = try VBVirtualMachine(bundleURL: root.appendingPathComponent("Original.vbvm"), isNewInstall: true)
        try vm.saveMetadata()
        try body(vm)
    }

    private func add(_ tunnel: ServiceTunnel, to vm: VBVirtualMachine, policy: ServiceTunnelPolicy = .unrestricted) throws -> Bool {
        try vm.addServiceTunnelWithoutReview(tunnel, setting: setting, security: security, policy: policy)
    }

    private func enable(_ tunnel: ServiceTunnel, in vm: VBVirtualMachine, policy: ServiceTunnelPolicy = .unrestricted) throws -> Bool {
        try vm.enableServiceTunnelWithoutReview(tunnel.id, setting: setting, security: security, policy: policy)
    }

    private func reduce(_ vm: VBVirtualMachine, _ change: (inout [ServiceTunnel]) -> Void) throws {
        try vm.reduceApprovedServiceTunnels(change, setting: setting, security: security)
    }

    private func runnable(in vm: VBVirtualMachine) throws -> [ServiceTunnel] {
        try vm.runnableServiceTunnels(setting: setting, security: security)
    }

    @Test func addingNeverSkipsTheReviewTheHostAsksFor() throws {
        try withVM { vm in
            level.value = .reviewAll
            #expect(try !add(web, to: vm))
            #expect(setting.read(from: vm) == .missing)

            level.value = .reviewNew
            #expect(try !add(web, to: vm))
            try storage.remember([ServiceTunnelIdentity(web)])
            #expect(try add(web, to: vm))
            #expect(try runnable(in: vm) == [web])
            #expect(try !add(database, to: vm))
            #expect(try runnable(in: vm) == [web])

            level.value = .reviewNone
            #expect(try add(database, to: vm))
            #expect(try runnable(in: vm) == [web, database])

            // Nothing that was added without a review counts as reviewed once the host asks for review again.
            level.value = .reviewAll
            #expect(try runnable(in: vm).isEmpty)
        }
    }

    @Test func addingLeavesTunnelsThatAwaitReviewAndApprovedOnesAlone() throws {
        try withVM { vm in
            level.value = .reviewAll
            try setting.store([web], in: vm)
            #expect(try !add(database, to: vm))
            #expect(setting.read(from: vm) == .needsApproval([web]))

            try setting.approve([web], in: vm)
            #expect(try !add(database, to: vm))
            #expect(try runnable(in: vm) == [web])

            level.value = .reviewNone
            let sameListener = ServiceTunnel(listensOnHost: true, listener: web.listener, destination: .tcp(22))
            #expect(throws: Failure.self) { try add(sameListener, to: vm) }

            var policy = ServiceTunnelPolicy()
            policy.hostServicesDisabled = true
            #expect(throws: Failure.self) { try add(database, to: vm, policy: policy) }
            #expect(try runnable(in: vm) == [web])
        }
    }

    @Test func turningOffAndRemovingKeepsTheRestApproved() throws {
        try withVM { vm in
            level.value = .reviewAll
            try setting.approve([web, database], in: vm)

            try reduce(vm) { $0[0].isEnabled = false }
            var off = web
            off.isEnabled = false
            #expect(setting.read(from: vm) == .approved([off, database]))

            try reduce(vm) { $0.removeAll { $0.id == database.id } }
            #expect(setting.read(from: vm) == .approved([off]))

            // Anything that isn't less than what was approved is refused.
            #expect(throws: Failure.self) { try reduce(vm) { $0[0].isEnabled = true } }
            #expect(throws: Failure.self) { try reduce(vm) { $0.append(database) } }
            #expect(setting.read(from: vm) == .approved([off]))

            try setting.store([web, database], in: vm)
            #expect(throws: Failure.self) { try reduce(vm) { $0.removeAll() } }
            #expect(setting.read(from: vm) == .needsApproval([web, database]))
        }
    }

    @Test func turningOnFollowsTheReviewLevel() throws {
        try withVM { vm in
            var off = web
            off.isEnabled = false

            level.value = .reviewAll
            try vm.approveServiceTunnels([off], setting: setting, security: security)
            #expect(try !enable(off, in: vm))
            #expect(try runnable(in: vm) == [off])

            // Approving the tunnels remembered the port, which is what this level goes by.
            level.value = .reviewNew
            #expect(try enable(off, in: vm))
            #expect(try runnable(in: vm) == [web])
            #expect(try enable(web, in: vm))

            try reduce(vm) { $0[0].isEnabled = false }
            var policy = ServiceTunnelPolicy()
            policy.guestServicesDisabled = true
            #expect(throws: Failure.self) { try enable(off, in: vm, policy: policy) }
            #expect(throws: Failure.self) { try enable(database, in: vm) }

            level.value = .reviewNone
            #expect(try enable(off, in: vm))
            #expect(try runnable(in: vm) == [web])
        }
    }
}
