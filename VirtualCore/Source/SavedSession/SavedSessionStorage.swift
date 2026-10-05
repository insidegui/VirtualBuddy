import Foundation
import OSLog

/// Everything needed to capture a session, gathered while the virtual machine is still running.
///
/// `@unchecked Sendable` because the configuration is a plain value that is never mutated after it is captured.
struct SavedSessionCapturePlan: @unchecked Sendable {
    struct ResourceSource: Sendable {
        var id: String
        var role: SavedSessionManifest.Role
        var sourceURL: URL
        /// Where the resource lives while the virtual machine runs, relative to the bundle.
        var workingPath: String
    }

    var sessionID = UUID()
    var resources: [ResourceSource]
    /// The configuration that was used to construct the running virtual machine.
    var configuration: VBMacConfiguration
    var runtimeDescription: SavedSessionRuntimeDescription
    var screenshotSourceURL: URL?
    var wasPausedBeforeSave: Bool
    var memorySize: UInt64
}

/// A package that's being built in a private staging directory.
struct SavedSessionStagedCapture: Sendable {
    let plan: SavedSessionCapturePlan
    let stagingURL: URL
    let resources: [SavedSessionManifest.Resource]
    let screenshotFileName: String?

    /// Where the framework must write the memory and device state.
    var stateFileURL: URL { stagingURL.appending(path: SavedSessionLayout.stateFileName) }
}

/// What the virtual machine needs in order to be restored.
///
/// `@unchecked Sendable` because the configuration is a plain value that is never mutated after it is decoded.
struct SavedSessionRestorePreparation: @unchecked Sendable {
    let manifest: SavedSessionManifest
    /// The immutable memory and device state in the saved package.
    let stateFileURL: URL
    /// The configuration that was captured when the session was saved.
    let configuration: VBMacConfiguration
    /// The guest additions image that was attached when the session was saved, installed in a working location.
    let guestAdditionsMediaURL: URL?
}

/// Reads and writes saved session packages inside a virtual machine bundle.
///
/// ## Package lifecycle
///
/// A package is built in a private staging directory, validated, and only then published with a single atomic rename.
/// A package that's visible is always complete.
///
/// Restoring is a transaction described by a durable journal:
///
/// 1. `staging`: clones of the saved resources are created next to the virtual machine. Nothing has been modified.
/// 2. `promoting`: working resources are moved aside and replaced by the staged clones.
/// 3. `promoted`: every working resource has been replaced. The virtual machine has not been resumed.
/// 4. `consumed`: written before execution can begin. From this point on, the saved package no longer describes the virtual machine's disks.
///
/// Interruptions before `consumed` are rolled back. An interruption after `consumed` is never replayed automatically,
/// the user has to decide what to do. Once resuming succeeded, the package is removed.
struct SavedSessionStorage: Sendable {
    let layout: SavedSessionLayout
    let fileSystem: SavedSessionFileSystem
    let hostECID: UInt64?

    private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "SavedSessionStorage")

    init(bundleURL: URL, fileSystem: SavedSessionFileSystem = DefaultSavedSessionFileSystem(), hostECID: UInt64? = ProcessInfo.processInfo.machineECID) {
        self.layout = SavedSessionLayout(bundleURL: bundleURL)
        self.fileSystem = fileSystem
        self.hostECID = hostECID
    }

    private static let encoder = PropertyListEncoder()
    private static let decoder = PropertyListDecoder()

    // MARK: Inspection

    /// Reads the current condition of the virtual machine's saved session without modifying anything.
    func inspect() -> VBSavedSessionDescriptor? {
        guard fileSystem.exists(layout.manifestURL) else { return nil }

        let manifest: SavedSessionManifest
        do {
            manifest = try readManifest()
        } catch {
            return VBSavedSessionDescriptor(
                id: UUID(),
                date: nil,
                status: .recoveryRequired(.unavailable(error.localizedDescription))
            )
        }

        let screenshotURL = manifest.screenshotFileName.map { layout.packageURL.appending(path: $0) }

        func descriptor(_ status: VBSavedSessionDescriptor.Status) -> VBSavedSessionDescriptor {
            VBSavedSessionDescriptor(id: manifest.id, date: manifest.date, status: status, screenshotURL: screenshotURL)
        }

        do {
            if let journal = try readJournal(), journal.sessionID == manifest.id, journal.phase == .consumed {
                return descriptor(.recoveryRequired(.interruptedAfterResume))
            }
            try validate(manifest, in: layout.packageURL)
            return descriptor(.ready)
        } catch {
            return descriptor(.recoveryRequired(.unavailable(error.localizedDescription)))
        }
    }

    // MARK: Capture

    /// Creates the staging directory and clones every resource into it.
    func stageCapture(_ plan: SavedSessionCapturePlan) throws -> SavedSessionStagedCapture {
        guard !fileSystem.exists(layout.packageURL), !fileSystem.exists(layout.transactionURL) else {
            throw SavedSessionError.activeSessionConflict
        }

        guard layout.bundleURL.volumeSupportsFileCloning else {
            throw SavedSessionError.notEligible(.volumeDoesNotSupportCloning)
        }

        try removeTransientDirectories()

        for resource in plan.resources where !fileSystem.exists(resource.sourceURL) {
            throw SavedSessionError.missingResource(resource.sourceURL.lastPathComponent)
        }

        try ensureEnoughSpace(forMemorySize: plan.memorySize)

        let stagingURL = layout.stagingURL(for: plan.sessionID)

        do {
            try fileSystem.createDirectory(stagingURL)
            let resourcesURL = stagingURL.appending(path: SavedSessionLayout.resourcesDirectoryName, directoryHint: .isDirectory)
            try fileSystem.createDirectory(resourcesURL)

            var stagedResources = [SavedSessionManifest.Resource]()

            for (index, source) in plan.resources.enumerated() {
                try Task.checkCancellation()

                let name = "\(source.role.rawValue)-\(index)"
                let destination = resourcesURL.appending(path: name)

                guard let sourceSize = fileSystem.byteCount(of: source.sourceURL) else {
                    throw SavedSessionError.missingResource(source.sourceURL.lastPathComponent)
                }

                try fileSystem.clone(from: source.sourceURL, to: destination)

                guard fileSystem.byteCount(of: destination) == sourceSize else {
                    throw SavedSessionError.resourceSizeMismatch(source.sourceURL.lastPathComponent)
                }

                stagedResources.append(SavedSessionManifest.Resource(
                    id: source.id,
                    role: source.role,
                    packagePath: "\(SavedSessionLayout.resourcesDirectoryName)/\(name)",
                    workingPath: source.workingPath,
                    byteCount: sourceSize
                ))
            }

            let configurationData = try Self.encoder.encode(plan.configuration)
            try fileSystem.writeDurably(configurationData, to: stagingURL.appending(path: SavedSessionLayout.configurationFileName))

            var screenshotFileName: String?
            if let screenshotURL = plan.screenshotSourceURL, fileSystem.exists(screenshotURL) {
                /// A screenshot is only presentation, failing to copy one must not fail the save.
                do {
                    try fileSystem.clone(from: screenshotURL, to: stagingURL.appending(path: SavedSessionLayout.screenshotFileName))
                    screenshotFileName = SavedSessionLayout.screenshotFileName
                } catch {
                    logger.warning("Failed to copy screenshot into saved session: \(error, privacy: .public)")
                }
            }

            return SavedSessionStagedCapture(plan: plan, stagingURL: stagingURL, resources: stagedResources, screenshotFileName: screenshotFileName)
        } catch {
            try? fileSystem.remove(stagingURL)
            throw error
        }
    }

    /// Validates the staged package and publishes it with an atomic rename.
    ///
    /// The framework state file must already have been written to ``SavedSessionStagedCapture/stateFileURL``.
    func publish(_ staged: SavedSessionStagedCapture) throws -> VBSavedSessionDescriptor {
        do {
            guard let stateSize = fileSystem.byteCount(of: staged.stateFileURL), stateSize > 0 else {
                throw SavedSessionError.missingResource(SavedSessionLayout.stateFileName)
            }
            try fileSystem.synchronizeFile(staged.stateFileURL)

            let manifest = SavedSessionManifest(
                formatVersion: SavedSessionManifest.currentFormatVersion,
                id: staged.plan.sessionID,
                date: .now,
                appVersion: Bundle.main.vbShortVersionString,
                appBuild: Bundle.main.vbBuild,
                hostECID: hostECID,
                hostOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                stateFileName: SavedSessionLayout.stateFileName,
                stateFileByteCount: stateSize,
                configurationFileName: SavedSessionLayout.configurationFileName,
                screenshotFileName: staged.screenshotFileName,
                resources: staged.resources,
                runtimeDescription: staged.plan.runtimeDescription,
                wasPausedBeforeSave: staged.plan.wasPausedBeforeSave
            )

            try fileSystem.writeDurably(try Self.encoder.encode(manifest), to: staged.stagingURL.appending(path: SavedSessionLayout.manifestFileName))

            try validate(manifest, in: staged.stagingURL)

            try Task.checkCancellation()

            try fileSystem.synchronizeDirectory(staged.stagingURL)
            try fileSystem.move(from: staged.stagingURL, to: layout.packageURL, replacingExisting: false)

            /// The package is visible from here on. A failure to flush the directory doesn't make it incomplete.
            try? fileSystem.synchronizeDirectory(layout.bundleURL)

            return VBSavedSessionDescriptor(
                id: manifest.id,
                date: manifest.date,
                status: .ready,
                screenshotURL: manifest.screenshotFileName.map { layout.packageURL.appending(path: $0) }
            )
        } catch {
            try? fileSystem.remove(staged.stagingURL)
            throw error
        }
    }

    func abandon(_ staged: SavedSessionStagedCapture) {
        try? fileSystem.remove(staged.stagingURL)
    }

    /// The configuration that was captured when the session was saved.
    func capturedConfiguration() throws -> VBMacConfiguration {
        try readConfiguration(of: try readManifest())
    }

    private func readConfiguration(of manifest: SavedSessionManifest) throws -> VBMacConfiguration {
        do {
            return try Self.decoder.decode(VBMacConfiguration.self, from: fileSystem.read(layout.packageURL.appending(path: manifest.configurationFileName)))
        } catch {
            throw SavedSessionError.invalidManifest("The saved configuration could not be read.")
        }
    }

    // MARK: Restore

    /// Validates the saved session and installs clones of its resources in the virtual machine's working locations.
    ///
    /// Anything that goes wrong is rolled back, leaving the saved session available for another attempt.
    func prepareRestore() throws -> SavedSessionRestorePreparation {
        try recover()

        if let journal = try readJournal() {
            /// Recovery only leaves a journal behind when it can't be replayed safely.
            if journal.phase == .consumed { throw SavedSessionError.recoveryRequired(.interruptedAfterResume) }
            throw SavedSessionError.operationInProgress
        }

        guard fileSystem.exists(layout.manifestURL) else { throw SavedSessionError.noSavedSession }

        let manifest = try readManifest()
        try validate(manifest, in: layout.packageURL)

        let configuration = try readConfiguration(of: manifest)

        let entries = manifest.resources.enumerated().map { index, resource in
            SavedSessionJournal.Entry(
                resourceID: resource.id,
                workingPath: resource.workingPath,
                stagedName: "\(index)",
                backupName: "\(index)",
                hadOriginal: fileSystem.exists(layout.workingURL(for: resource.workingPath))
            )
        }

        var journal = SavedSessionJournal(sessionID: manifest.id, phase: .staging, entries: entries, startedAt: .now)

        do {
            try fileSystem.createDirectory(layout.transactionURL)
            try fileSystem.createDirectory(layout.stagedURL)
            try fileSystem.createDirectory(layout.backupURL)
            try writeJournal(journal)

            for (resource, entry) in zip(manifest.resources, entries) {
                try Task.checkCancellation()
                try fileSystem.clone(
                    from: layout.packageURL.appending(path: resource.packagePath),
                    to: layout.stagedURL.appending(path: entry.stagedName)
                )
            }

            try fileSystem.synchronizeDirectory(layout.stagedURL)

            try Task.checkCancellation()

            journal.phase = .promoting
            try writeJournal(journal)

            for entry in entries {
                let workingURL = layout.workingURL(for: entry.workingPath)

                if entry.hadOriginal {
                    try fileSystem.move(from: workingURL, to: layout.backupURL.appending(path: entry.backupName), replacingExisting: false)
                }

                try fileSystem.createDirectory(workingURL.deletingLastPathComponent())
                try fileSystem.move(from: layout.stagedURL.appending(path: entry.stagedName), to: workingURL, replacingExisting: false)
            }

            try fileSystem.synchronizeDirectory(layout.bundleURL)

            journal.phase = .promoted
            try writeJournal(journal)
        } catch {
            logger.error("Restore preparation failed, rolling back: \(error, privacy: .public)")
            try? rollback()
            throw error
        }

        let mediaURL = manifest.resource(with: .guestAdditionsMedia).map { layout.workingURL(for: $0.workingPath) }

        return SavedSessionRestorePreparation(
            manifest: manifest,
            stateFileURL: layout.packageURL.appending(path: manifest.stateFileName),
            configuration: configuration,
            guestAdditionsMediaURL: mediaURL
        )
    }

    /// Undoes a prepared restore. Only valid before ``markConsumed(_:)``.
    func cancelRestore() throws {
        try rollback()
    }

    /// Durably records that resuming is about to be requested.
    ///
    /// Execution can begin writing to the disks before the framework reports that it resumed, so this must
    /// be on stable storage before resuming.
    func markConsumed(_ preparation: SavedSessionRestorePreparation) throws {
        guard var journal = try readJournal(), journal.sessionID == preparation.manifest.id, journal.phase == .promoted else {
            throw SavedSessionError.operationInProgress
        }

        journal.phase = .consumed
        try writeJournal(journal)
    }

    /// Removes the consumed package after the virtual machine resumed.
    ///
    /// A failure after the package left its published location doesn't make it eligible again,
    /// since the consumed journal outlives the package.
    func completeRestore() throws {
        guard let journal = try readJournal(), journal.phase == .consumed else { return }

        try retirePackage(sessionID: journal.sessionID)
        try fileSystem.remove(layout.transactionURL)
    }

    /// Whether a consumed restore is waiting to be completed.
    func hasPendingConsumedRestore() -> Bool {
        (try? readJournal())?.phase == .consumed
    }

    // MARK: Recovery

    enum RecoveryOutcome: Equatable, Sendable {
        case nothingToRecover
        case rolledBack
        /// Execution may have started. Needs an explicit decision.
        case consumedSessionRetained
    }

    /// Finishes or rolls back whatever a previous run left behind. Safe to call at any time while no operation is running.
    @discardableResult
    func recover() throws -> RecoveryOutcome {
        try removeTransientDirectories()

        guard fileSystem.exists(layout.transactionURL) else { return .nothingToRecover }

        guard let journal = try readJournal() else {
            /// Interrupted before the journal was written, so nothing was touched.
            try fileSystem.remove(layout.transactionURL)
            return .nothingToRecover
        }

        switch journal.phase {
        case .staging, .promoting, .promoted:
            try rollback()
            return .rolledBack
        case .consumed:
            guard fileSystem.exists(layout.manifestURL) else {
                /// The package was already retired, only cleanup was left to do.
                try fileSystem.remove(layout.transactionURL)
                return .nothingToRecover
            }
            return .consumedSessionRetained
        }
    }

    /// Keeps the virtual machine's disks as they are and forgets the saved session.
    func discard() throws {
        try recover()

        if let manifest = try? readManifest() {
            try retirePackage(sessionID: manifest.id)
        } else if fileSystem.exists(layout.packageURL) {
            try retirePackage(sessionID: UUID())
        }

        try fileSystem.remove(layout.transactionURL)
        try removeWorkingMedia()
    }

    /// Makes a session that was interrupted after resuming eligible for restoration again, accepting that
    /// restoring it rewinds everything that happened since.
    func reinstateConsumedSession() throws {
        guard let journal = try readJournal(), journal.phase == .consumed else { return }
        try fileSystem.remove(layout.transactionURL)
    }

    func removeWorkingMedia() throws {
        try fileSystem.remove(layout.mediaDirectoryURL)
    }

    // MARK: Internals

    private func readManifest() throws -> SavedSessionManifest {
        let manifest: SavedSessionManifest
        do {
            manifest = try Self.decoder.decode(SavedSessionManifest.self, from: fileSystem.read(layout.manifestURL))
        } catch {
            throw SavedSessionError.invalidManifest("The manifest could not be read.")
        }

        guard manifest.formatVersion >= 1 else { throw SavedSessionError.invalidManifest("The manifest version is invalid.") }
        guard manifest.formatVersion <= SavedSessionManifest.currentFormatVersion else {
            throw SavedSessionError.unsupportedFormat(manifest.formatVersion)
        }

        return manifest
    }

    private func validate(_ manifest: SavedSessionManifest, in packageURL: URL) throws {
        if let savedECID = manifest.hostECID, let hostECID, savedECID != hostECID {
            throw SavedSessionError.hostMismatch
        }

        func requireFile(_ name: String, byteCount: UInt64?) throws {
            guard let size = fileSystem.byteCount(of: packageURL.appending(path: name)) else {
                throw SavedSessionError.missingResource(name)
            }
            if let byteCount, size != byteCount {
                throw SavedSessionError.resourceSizeMismatch(name)
            }
        }

        try requireFile(manifest.stateFileName, byteCount: manifest.stateFileByteCount)
        try requireFile(manifest.configurationFileName, byteCount: nil)

        for resource in manifest.resources {
            try requireFile(resource.packagePath, byteCount: resource.byteCount)
        }
    }

    private func readJournal() throws -> SavedSessionJournal? {
        guard fileSystem.exists(layout.journalURL) else { return nil }
        do {
            return try Self.decoder.decode(SavedSessionJournal.self, from: fileSystem.read(layout.journalURL))
        } catch {
            throw SavedSessionError.invalidManifest("The restore journal could not be read.")
        }
    }

    private func writeJournal(_ journal: SavedSessionJournal) throws {
        try fileSystem.writeDurably(try Self.encoder.encode(journal), to: layout.journalURL)
    }

    /// Puts every working resource back the way it was before the restore transaction started.
    private func rollback() throws {
        if let journal = try readJournal() {
            for entry in journal.entries {
                let workingURL = layout.workingURL(for: entry.workingPath)
                let backupURL = layout.backupURL.appending(path: entry.backupName)

                if fileSystem.exists(backupURL) {
                    /// The working resource was replaced (or is about to be), put the original back.
                    try fileSystem.remove(workingURL)
                    try fileSystem.move(from: backupURL, to: workingURL, replacingExisting: false)
                } else if !entry.hadOriginal {
                    /// Nothing existed before, so anything at the working location came from this transaction.
                    try fileSystem.remove(workingURL)
                    try removeDirectoryIfEmpty(workingURL.deletingLastPathComponent())
                }
            }

            try fileSystem.synchronizeDirectory(layout.bundleURL)
        }

        try fileSystem.remove(layout.transactionURL)
    }

    /// Removes a directory that was created for a working resource, never the bundle itself.
    private func removeDirectoryIfEmpty(_ url: URL) throws {
        guard url.standardizedFileURL != layout.bundleURL.standardizedFileURL, fileSystem.exists(url) else { return }
        guard try fileSystem.contentsOfDirectory(at: url).isEmpty else { return }
        try fileSystem.remove(url)
    }

    /// Atomically moves the package out of its published location, then deletes it.
    private func retirePackage(sessionID: UUID) throws {
        guard fileSystem.exists(layout.packageURL) else { return }

        let obsoleteURL = layout.obsoleteURL(for: sessionID)
        try fileSystem.remove(obsoleteURL)
        try fileSystem.move(from: layout.packageURL, to: obsoleteURL, replacingExisting: false)
        try? fileSystem.synchronizeDirectory(layout.bundleURL)

        do {
            try fileSystem.remove(obsoleteURL)
        } catch {
            /// Leftovers are collected by ``removeTransientDirectories()``, and can't be restored from.
            logger.warning("Failed to remove obsolete saved session: \(error, privacy: .public)")
        }
    }

    private func removeTransientDirectories() throws {
        for url in try fileSystem.contentsOfDirectory(at: layout.bundleURL) {
            let name = url.lastPathComponent
            if name.hasPrefix(SavedSessionLayout.stagingPrefix) || name.hasPrefix(SavedSessionLayout.obsoletePrefix) {
                try fileSystem.remove(url)
            }
        }
    }

    private func ensureEnoughSpace(forMemorySize memorySize: UInt64) throws {
        guard let free = layout.bundleURL.freeDiskSpaceOnVolume else { return }

        /// The memory image is written in full, and the clones will diverge from their originals as the guest runs.
        let required = memorySize + Self.spaceMargin
        guard free >= required else { throw SavedSessionError.diskFull }
    }

    private static let spaceMargin: UInt64 = 1 << 30
}
