import Foundation

/// A condition that prevents a saved session from being resumed without an explicit decision from the user.
public enum SavedSessionIssue: Hashable, Sendable {
    /// The session was resumed in an earlier run of the app, so the virtual machine's disks may have been written to since.
    /// Restoring the retained save would rewind those changes.
    case interruptedAfterResume
    /// The session was saved, but the virtual machine couldn't be stopped afterwards.
    case stopFailedAfterSave(String)
    /// The saved session can't be used, for example because a required file is missing or it belongs to a different host.
    case unavailable(String)

    /// The session was saved, but the virtual machine that was saved is still there.
    public var isStopFailure: Bool {
        if case .stopFailedAfterSave = self { true } else { false }
    }

    public var explanation: String {
        switch self {
        case .interruptedAfterResume:
            "This virtual machine was resumed from its saved session, but the app quit before that finished cleanly. The virtual machine's disks may have changed since, so restoring the retained session would rewind those changes."
        case .stopFailedAfterSave(let reason):
            "The session was saved, but the virtual machine could not be stopped. \(reason)"
        case .unavailable(let reason):
            reason
        }
    }
}

/// Describes the saved session that belongs to a virtual machine, if any.
public struct VBSavedSessionDescriptor: Identifiable, Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case ready
        case recoveryRequired(SavedSessionIssue)
    }

    public var id: UUID
    public var date: Date?
    public var status: Status
    public var screenshotURL: URL?

    public var issue: SavedSessionIssue? {
        guard case .recoveryRequired(let issue) = status else { return nil }
        return issue
    }

    public var isReady: Bool { status == .ready }

    public init(id: UUID, date: Date?, status: Status, screenshotURL: URL? = nil) {
        self.id = id
        self.date = date
        self.status = status
        self.screenshotURL = screenshotURL
    }
}

// MARK: - Manifest

/// Describes the contents of a saved session package. The manifest is the last thing written to a package,
/// and a package is only ever visible once it's complete.
struct SavedSessionManifest: Codable, Hashable, Sendable {
    static let currentFormatVersion = 1

    enum Role: String, Codable, Sendable {
        case disk
        case auxiliaryStorage
        case machineIdentifier
        case hardwareModel
        case guestAdditionsMedia
    }

    struct Resource: Codable, Hashable, Sendable {
        var id: String
        var role: Role
        /// Path of the clone inside the package, relative to the package directory.
        var packagePath: String
        /// Path where the resource lives while the virtual machine is running, relative to the virtual machine bundle.
        var workingPath: String
        var byteCount: UInt64
    }

    var formatVersion: Int
    var id: UUID
    var date: Date
    var appVersion: String
    var appBuild: Int
    var hostECID: UInt64?
    var hostOSVersion: String
    var stateFileName: String
    var stateFileByteCount: UInt64
    var configurationFileName: String
    var screenshotFileName: String?
    var resources: [Resource]
    var runtimeDescription: SavedSessionRuntimeDescription
    var wasPausedBeforeSave: Bool

    func resource(with role: Role) -> Resource? {
        resources.first { $0.role == role }
    }
}

// MARK: - Journal

/// Durable record of an in-progress restore transaction. See ``SavedSessionStorage`` for the state machine.
struct SavedSessionJournal: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Sendable {
        /// Clones of the saved resources are being created. Nothing in the virtual machine's working locations has been touched.
        case staging
        /// Working resources are being replaced by the staged clones.
        case promoting
        /// All working resources have been replaced, the virtual machine has not been resumed.
        case promoted
        /// Resuming has been requested. The virtual machine may have written to its disks.
        case consumed
    }

    struct Entry: Codable, Hashable, Sendable {
        var resourceID: String
        var workingPath: String
        var stagedName: String
        var backupName: String
        /// Whether a file existed at the working location when the transaction started.
        var hadOriginal: Bool
    }

    var sessionID: UUID
    var phase: Phase
    var entries: [Entry]
    var startedAt: Date
}

// MARK: - Layout

/// Locations of every file the saved session machinery manages inside a virtual machine bundle.
struct SavedSessionLayout: Sendable {
    static let packageName = ".vbsession"
    static let stagingPrefix = ".vbsession-staging-"
    static let obsoletePrefix = ".vbsession-obsolete-"
    static let transactionName = ".vbsession-transaction"
    static let mediaDirectoryName = ".vbsession-media"

    static let manifestFileName = "Manifest.plist"
    static let stateFileName = "State.vzvmsave"
    static let configurationFileName = "Configuration.plist"
    static let screenshotFileName = "Screenshot.heic"
    static let resourcesDirectoryName = "Resources"
    static let journalFileName = "Journal.plist"
    static let stagedDirectoryName = "Staged"
    static let backupDirectoryName = "Backup"
    static let guestAdditionsMediaWorkingPath = "\(mediaDirectoryName)/GuestAdditions.img"

    let bundleURL: URL

    var packageURL: URL { bundleURL.appending(path: Self.packageName, directoryHint: .isDirectory) }
    var manifestURL: URL { packageURL.appending(path: Self.manifestFileName) }
    var transactionURL: URL { bundleURL.appending(path: Self.transactionName, directoryHint: .isDirectory) }
    var journalURL: URL { transactionURL.appending(path: Self.journalFileName) }
    var stagedURL: URL { transactionURL.appending(path: Self.stagedDirectoryName, directoryHint: .isDirectory) }
    var backupURL: URL { transactionURL.appending(path: Self.backupDirectoryName, directoryHint: .isDirectory) }
    var mediaDirectoryURL: URL { bundleURL.appending(path: Self.mediaDirectoryName, directoryHint: .isDirectory) }

    func stagingURL(for id: UUID) -> URL {
        bundleURL.appending(path: Self.stagingPrefix + id.uuidString, directoryHint: .isDirectory)
    }

    func obsoleteURL(for id: UUID) -> URL {
        bundleURL.appending(path: Self.obsoletePrefix + id.uuidString, directoryHint: .isDirectory)
    }

    func workingURL(for relativePath: String) -> URL {
        bundleURL.appending(path: relativePath, directoryHint: .notDirectory)
    }

    /// Names of items in a virtual machine bundle that must never be copied when duplicating it.
    static func isTransientName(_ name: String) -> Bool {
        name.hasPrefix(stagingPrefix)
            || name.hasPrefix(obsoletePrefix)
            || name == transactionName
            || name == mediaDirectoryName
    }
}

// MARK: - Errors

public enum SavedSessionError: LocalizedError {
    case notEligible(SavedSessionEligibility.Issue)
    case cloneUnsupported(URL)
    case diskFull
    case missingResource(String)
    case resourceSizeMismatch(String)
    case invalidManifest(String)
    case unsupportedFormat(Int)
    case hostMismatch
    case configurationChanged(String)
    case noSavedSession
    case recoveryRequired(SavedSessionIssue)
    case activeSessionConflict
    case operationInProgress
    case stopFailedAfterSave(Error)
    case restoreFailed(Error)
    case policyBlocksResume(String)
    case activeCopyConflict([SavedSessionActiveCopyConflict])
    case discardConfirmationRequired
    case io(operation: String, path: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .notEligible(let issue):
            issue.explanation
        case .cloneUnsupported:
            "The volume where this virtual machine is stored doesn't support the file cloning that saved sessions require."
        case .diskFull:
            "There isn't enough free space on the volume to save this virtual machine's session."
        case .missingResource(let name):
            "The saved session is missing a required file (\(name))."
        case .resourceSizeMismatch(let name):
            "A file in the saved session (\(name)) is incomplete."
        case .invalidManifest(let reason):
            "The saved session is damaged. \(reason)"
        case .unsupportedFormat:
            "The saved session was created by a newer version of VirtualBuddy."
        case .hostMismatch:
            "This saved session belongs to a different Mac. Saved sessions can't be resumed on a different host."
        case .configurationChanged(let reason):
            "The saved session can't be resumed because the virtual machine's hardware would be different from when it was saved. \(reason)"
        case .noSavedSession:
            "This virtual machine doesn't have a saved session."
        case .recoveryRequired(let issue):
            issue.explanation
        case .activeSessionConflict:
            "A saved session can't be created while another one still exists for this virtual machine."
        case .operationInProgress:
            "Another operation is already in progress for this virtual machine."
        case .stopFailedAfterSave(let error):
            "The session was saved, but the virtual machine could not be stopped. \(error.localizedDescription)"
        case .restoreFailed(let error):
            "The saved session could not be restored. \(error.localizedDescription)"
        case .policyBlocksResume(let reason):
            reason
        case .activeCopyConflict(let conflicts):
            conflicts.first?.explanation
        case .discardConfirmationRequired:
            "Starting this virtual machine in this mode requires discarding its saved session."
        case .io(let operation, let path, let code):
            "File operation \(operation) failed for \(path): \(String(cString: strerror(code)))."
        }
    }
}

/// Another virtual machine that is running and can't coexist with the one that's being resumed.
public struct SavedSessionActiveCopyConflict: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        case guestIdentity
        case macAddress(String)
    }

    public var virtualMachineID: VBVirtualMachine.ID
    public var name: String
    public var reason: Reason

    public init(virtualMachineID: VBVirtualMachine.ID, name: String, reason: Reason) {
        self.virtualMachineID = virtualMachineID
        self.name = name
        self.reason = reason
    }

    /// Finds the running virtual machines that can't run at the same time as one that's about to resume a saved session.
    ///
    /// A copy of a virtual machine keeps the guest identity and the network addresses that its session was saved with,
    /// and a resumed guest can't be given different ones. Running both at once would put two guests with the same identity on the network.
    static func conflicts(for vm: VBVirtualMachine, macAddresses: [String], among running: [VBVirtualMachine]) -> [SavedSessionActiveCopyConflict] {
        let addresses = Set(macAddresses.map { $0.uppercased() }.filter { !$0.isEmpty })
        let identity = try? Data(contentsOf: vm.machineIdentifierURL)

        var conflicts = [SavedSessionActiveCopyConflict]()

        for other in running where other.id != vm.id {
            if let identity, (try? Data(contentsOf: other.machineIdentifierURL)) == identity {
                conflicts.append(SavedSessionActiveCopyConflict(virtualMachineID: other.id, name: other.name, reason: .guestIdentity))
                continue
            }

            let otherAddresses = other.configuration.hardware.networkDevices.map { $0.macAddress.uppercased() }
            if let shared = otherAddresses.first(where: addresses.contains) {
                conflicts.append(SavedSessionActiveCopyConflict(virtualMachineID: other.id, name: other.name, reason: .macAddress(shared)))
            }
        }

        return conflicts
    }

    public var explanation: String {
        switch reason {
        case .guestIdentity:
            "\"\(name)\" is running and has the same guest identity as this virtual machine. Two virtual machines with the same identity can't run at the same time."
        case .macAddress(let address):
            "\"\(name)\" is running and uses the same network address (\(address)) that this virtual machine had when its session was saved."
        }
    }
}
