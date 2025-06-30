//
//  VMLibraryController.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 10/04/22.
//

import SwiftUI
import Combine
import OSLog
import BuddyFoundation

@MainActor
public final class VMLibraryController: ObservableObject {

    private let logger = Logger(for: VMLibraryController.self)

    public enum State: Identifiable {
        public enum ID: Int {
            case loading
            case loaded
            case empty
            case volumeNotMounted
            case directoryMissing
        }

        public var id: ID {
            switch self {
            case .loading: .loading
            case .loaded: .loaded
            case .empty: .empty
            case .volumeNotMounted: .volumeNotMounted
            case .directoryMissing: .directoryMissing
            }
        }

        case loading
        case loaded([VBVirtualMachine])
        case empty
        case volumeNotMounted
        case directoryMissing

        var isVolumeNotMounted: Bool { id == .volumeNotMounted }
    }
    
    @Published public private(set) var state = State.loading {
        didSet {
            if case .loaded(let machines) = state {
                self.virtualMachines = machines
            } else {
                self.virtualMachines = []
            }
        }
    }
    
    @Published public private(set) var virtualMachines: [VBVirtualMachine] = []

    /// Identifiers for all VMs that are currently in a "booted" state (starting, booted, or paused).
    @Published public private(set) var bootedMachineIdentifiers = Set<VBVirtualMachine.ID>()
    private let bootedInstances = NSMapTable<NSString, VMInstance>(keyOptions: [.objectPersonality, .strongMemory], valueOptions: [.objectPersonality, .weakMemory])

    /// Populated when ``bootedMachineIdentifiers`` is not empty, invalidated when the last booted machine identifier is unregistered via ``unregisterBootedVM(identifier:)``.
    private var preventTerminationAssertion: PreventTerminationAssertion?

    /// Observes notifications about volume mount/unmount that are used when library resides in a removable volume.
    private var volumeNotificationsTask: Task<Void, Never>?

    /// Set when the library is loaded.
    private var isLibraryInRemovableVolume = false

    let settingsContainer: VBSettingsContainer

    private let filePresenter: DirectoryObserver
    private let updateSignal = PassthroughSubject<URL, Never>()

    private static let observedFileExtensions: Set<String> = [
        VBVirtualMachine.bundleExtension,
        "plist",
        "heic"
    ]

    public init(settingsContainer: VBSettingsContainer = .current) {
        self.settingsContainer = settingsContainer
        self.settings = settingsContainer.settings
        self.libraryURL = settingsContainer.settings.libraryURL
        self.filePresenter = DirectoryObserver(
            presentedItemURL: settingsContainer.settings.libraryURL,
            fileExtensions: Self.observedFileExtensions,
            label: "Library",
            signal: updateSignal
        )

        loadMachines()
        bind()
    }

    private var settings: VBSettings {
        didSet {
            self.libraryURL = settings.libraryURL
        }
    }

    @Published
    public private(set) var libraryURL: URL {
        didSet {
            guard oldValue != libraryURL else { return }
            stopObservingRemovableVolumeNotifications()
            loadMachines()
        }
    }

    private lazy var cancellables = Set<AnyCancellable>()
    
    private lazy var fileManager = FileManager()

    private var hasLoadedMachinesOnce = false

    private func bind() {
        settingsContainer.$settings.sink { [weak self] newSettings in
            self?.settings = newSettings
        }
        .store(in: &cancellables)

        updateSignal
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] url in
                guard let self else { return }

                /// Ignore file change notifications in the guest additions or downloads directories.
                guard !url.path.contains(GuestAdditionsDiskImage.imagesRootURL.path) else {
                    return
                }
                guard !url.path.contains(VBSettings.current.downloadsDirectoryURL.path) else {
                    return
                }

                guard let bundleURL = url.virtualMachineBundleParent else {
                    self.logger.fault("Failed to determine VM bundle URL for changed file \(url.lastPathComponent)")
                    return
                }

                self.handleBundleChanged(at: bundleURL)
            }
            .store(in: &cancellables)
    }

    private func handleBundleChanged(at bundleURL: URL) {
        logger.debug("Bundle changed: \(bundleURL.lastPathComponent)")

        loadMachines()
    }

    public func loadMachines(createLibrary: Bool = false) {
        #if DEBUG
        guard !simulateState() else { return }
        #endif

        let path = libraryURL.path

        logger.debug("Loading machines from \(path.quoted)")

        if createLibrary, !libraryURL.isReadableDirectory {
            do {
                try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            } catch {
                NSApp.presentError(error)
                return
            }
        }

        isLibraryInRemovableVolume = Self.isLibraryURLInRemovableVolume(libraryURL)

        observeRemovableVolumeNotifications()

        guard libraryURL.isReadableDirectory else {
            if isLibraryInRemovableVolume {
                logger.warning("External volume library directory not found at \(path.quoted)")

                state = .volumeNotMounted
            } else {
                logger.warning("Library directory not found at \(path.quoted)")

                state = .directoryMissing
            }
            return
        }

        filePresenter.presentedItemURL = libraryURL

        guard let enumerator = fileManager.enumerator(at: libraryURL, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants], errorHandler: nil) else {
            logger.fault("Failed to create directory enumerator for library at \(path.quoted)")
            state = .directoryMissing
            return
        }
        
        var machines = [VBVirtualMachine]()

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == VBVirtualMachine.bundleExtension else { continue }
            
            do {
                let machine = try VBVirtualMachine(bundleURL: url, createIfNeeded: false)

                if let index = machines.firstIndex(where: { $0.id == machine.id }) {
                    machines[index] = machine
                } else {
                    machines.append(machine)
                }
            } catch is VBVirtualMachine.BundleDirectoryMissingError {
                /// This error can occur when the bundle is deleted in Finder.
                logger.debug("Ignoring BundleDirectoryMissingError for \(url.lastPathComponent)")
            } catch {
                assertionFailure("Failed to construct VM model: \(error)")
            }
        }

        let sortedMachines = machines.sorted(by: { $0.bundleURL.creationDate > $1.bundleURL.creationDate })

        self.state = sortedMachines.isEmpty ? .empty : .loaded(sortedMachines)

        if !hasLoadedMachinesOnce {
            hasLoadedMachinesOnce = true

            migrateBackgroundHashesForLegacyThumbnails()
        }
    }

    public func reload(animated: Bool = true) {
        if animated {
            withAnimation(.spring()) {
                loadMachines()
            }
        } else {
            loadMachines()
        }
    }

    public func validateNewName(_ name: String, for vm: VBVirtualMachine) throws {
        /// No need to validate if name is not changed.
        guard name != vm.name else { return }

        try urlForRenaming(vm, to: name)
    }

    // MARK: - VM Controller References

    private final class Coordinator {
        private let lock = NSRecursiveLock()

        private var _activeVMControllers = [VBVirtualMachine.ID: WeakReference<VMController>]()

        /// References to all active `VMController` instances by VM identifier.
        /// May hold references to invalidated controllers because this does not hold a strong reference to them.
        var activeVMControllers: [VBVirtualMachine.ID: WeakReference<VMController>] {
            get { lock.withLock { _activeVMControllers } }
            set { lock.withLock { _activeVMControllers = newValue } }
        }

        func activeController(for virtualMachineID: VBVirtualMachine.ID) -> VMController? {
            activeVMControllers[virtualMachineID]?.object
        }

        /// Called when a new `VMController` is initialized so that we can reference it
        /// outside the scope of the view hierarchy (for automation).
        func addController(_ controller: VMController) {
            activeVMControllers[controller.id] = WeakReference(controller)
        }

        /// Called when a `VMController` is dying so that we can cleanup our reference to it.
        func removeController(_ controller: VMController) {
            activeVMControllers[controller.id] = nil
        }
    }

    nonisolated(unsafe) private let coordinator = Coordinator()

    public nonisolated var activeVMControllers: [WeakReference<VMController>] { Array(coordinator.activeVMControllers.values) }

    public nonisolated func activeController(for virtualMachineID: VBVirtualMachine.ID) -> VMController? {
        coordinator.activeVMControllers[virtualMachineID]?.object
    }

    /// Called when a new `VMController` is initialized so that we can reference it
    /// outside the scope of the view hierarchy (for automation).
    nonisolated func addController(_ controller: VMController) {
        coordinator.activeVMControllers[controller.id] = WeakReference(controller)
    }

    /// Called when a `VMController` is dying so that we can cleanup our reference to it.
    nonisolated func removeController(_ controller: VMController) {
        coordinator.activeVMControllers[controller.id] = nil
    }

    // MARK: - Migration

    private var alwaysAttemptLegacyThumbnailMigration: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "VBAlwaysAttemptLegacyThumbnailMigration")
        #else
        false
        #endif
    }

    private static let migratedLegacyThumbnailBackgroundHashesDefaultsKey = "migratedLegacyThumbnailBackgroundHashes_2"
    private var migratedLegacyThumbnailBackgroundHashes: Bool {
        get {
            guard !alwaysAttemptLegacyThumbnailMigration else { return false }

            return UserDefaults.standard.bool(forKey: Self.migratedLegacyThumbnailBackgroundHashesDefaultsKey)
        }
        set {
            guard !alwaysAttemptLegacyThumbnailMigration else { return }

            UserDefaults.standard.set(newValue, forKey: Self.migratedLegacyThumbnailBackgroundHashesDefaultsKey)
        }
    }

    private func migrateBackgroundHashesForLegacyThumbnails() {
        guard !migratedLegacyThumbnailBackgroundHashes else { return }

        let machines = self.virtualMachines

        /// Skip setting migration flag for empty machines in case user library has not been mounted yet.
        guard !machines.isEmpty else { return }

        defer {
            migratedLegacyThumbnailBackgroundHashes = true
        }

        logger.debug("Generating missing background hashes for legacy thumbnails...")

        Task {
            let needingMigration = machines.filter { $0.configuration.systemType == .mac && $0.metadata.backgroundHash == .virtualBuddyBackground }
            guard !needingMigration.isEmpty else {
                logger.debug("Found no machines needing background hash migration.")
                return
            }

            logger.debug("Found machines needing background hash migration: \(needingMigration.map(\.name).formatted(.list(type: .and)))")

            for var machine in needingMigration {
                do {
                    guard let thumbnail = machine.thumbnailImage() else {
                        logger.debug("Ignoring \(machine.name) for background hash migration because it doesn't have a thumbnail.")
                        continue
                    }

                    if #available(macOS 15.0, *) {
                        let isDRMProtectedBug = await thumbnail.detectDRMProtectedVideoBug()

                        guard !isDRMProtectedBug else {
                            logger.notice("Invalidating thumbnail for \(machine.name): detected \"DRM Protected Video\" bug in its thumbnail.")
                            try machine.invalidateThumbnail()
                            try machine.invalidateScreenshot()
                            continue
                        }
                    }

                    let hash = try thumbnail.blurHash(numberOfComponents: (.vbBlurHashSize, .vbBlurHashSize))
                        .require("Background hash generation failed.")

                    machine.metadata.backgroundHash = BlurHashToken(value: hash)
                    try await MainActor.run { try machine.saveMetadata() }

                    logger.info("Migrated background hash for \(machine.name)")
                } catch {
                    logger.warning("Error migrating background hash for \(machine.name) - \(error, privacy: .public)")
                }
            }
        }
    }

}

// MARK: - Queries

public extension VMLibraryController {
    func virtualMachines(matching predicate: (VBVirtualMachine) -> Bool) -> [VBVirtualMachine] {
        virtualMachines.filter(predicate)
    }

    func virtualMachine(named name: String) -> VBVirtualMachine? {
        virtualMachines(matching: { $0.name.caseInsensitiveCompare(name) == .orderedSame }).first
    }
}

// MARK: - Management Actions

public extension VMLibraryController {

    @discardableResult
    func duplicate(_ vm: VBVirtualMachine) throws -> VBVirtualMachine {
        let newName = "Copy of " + vm.name

        let copyURL = try urlForRenaming(vm, to: newName)

        try fileManager.copyItem(at: vm.bundleURL, to: copyURL)

        var newVM = try VBVirtualMachine(bundleURL: copyURL)

        newVM.bundleURL.creationDate = .now
        newVM.uuid = UUID()

        try newVM.saveMetadata()

        reload()

        return newVM
    }

    func moveToTrash(_ vm: VBVirtualMachine) async throws {
        try await NSWorkspace.shared.recycle([vm.bundleURL])

        reload()
    }

    func rename(_ vm: VBVirtualMachine, to newName: String) throws {
        let newURL = try urlForRenaming(vm, to: newName)

        try fileManager.moveItem(at: vm.bundleURL, to: newURL)

        reload(animated: false)
    }

    @discardableResult
    func urlForRenaming(_ vm: VBVirtualMachine, to name: String) throws -> URL {
        guard name.count >= 3 else {
            throw Failure("Name must be at least 3 characters long.")
        }

        let newURL = vm
            .bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(name)
            .appendingPathExtension(VBVirtualMachine.bundleExtension)

        guard !fileManager.fileExists(atPath: newURL.path) else {
            throw Failure("Another virtual machine is already using this name, please choose another one.")
        }

        return newURL
    }
    
}

extension NSWorkspace: @retroactive @unchecked Sendable { }

// MARK: - Booted VM Tracking

public extension VMLibraryController {
    /// Adds virtual machine to the list of booted machines.
    func registerBootedVM(_ instance: VMInstance) {
        let id = instance.virtualMachineModel.id

        logger.debug("Registering booted VM \(id.shortID, privacy: .public)")

        bootedMachineIdentifiers.insert(id)
        bootedInstances.setObject(instance, forKey: id as NSString)

        startPreventingAppTerminationIfNeeded()
    }

    /// Removes virtual machine from the list of booted machines.
    func unregisterBootedVM(_ instance: VMInstance) {
        let id = instance.virtualMachineModel.id
        logger.debug("Unregistering booted VM \(id.shortID, privacy: .public)")

        bootedMachineIdentifiers.remove(id)
        bootedInstances.removeObject(forKey: id as NSString)

        stopPreventingAppTerminationIfNeeded()
    }

    func shutdownAll() {
        logger.debug(#function)

        for instance in bootedInstances.dictionaryRepresentation().values {
            let id = instance.virtualMachineModel.id
            Task {
                do {
                    logger.debug("Requesting stop for \(id.shortID, privacy: .public)")
                    
                    try await instance.stop()
                } catch {
                    logger.error("Error requesting stop for \(id.shortID, privacy: .public) - \(error, privacy: .public)")
                }
            }
        }
    }
}

// MARK: - App Termination Assertion

private extension VMLibraryController {
    func startPreventingAppTerminationIfNeeded() {
        guard !bootedMachineIdentifiers.isEmpty else { return }
        guard preventTerminationAssertion == nil || preventTerminationAssertion?.isValid == false else { return }

        logger.notice("Start preventing app termination")

        preventTerminationAssertion = NSApp.preventTermination(reason: "virtual machines are currently running", shouldTerminate: { [weak self] _ in
            self?.handleAppTerminationAttempt() ?? .terminateNow
        })
    }

    func stopPreventingAppTerminationIfNeeded() {
        guard bootedMachineIdentifiers.isEmpty else { return }
        guard preventTerminationAssertion != nil else { return }

        logger.notice("Stop preventing app termination")

        preventTerminationAssertion?.invalidate()
        preventTerminationAssertion = nil
    }

    func handleAppTerminationAttempt() -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Quit VirtualBuddy?"
        alert.informativeText = "VirtualBuddy is currently running virtual machines. Quitting the app without shutting them down first can result in data loss."

        let button = alert.addButton(withTitle: "Quit Now")
        button.hasDestructiveAction = true

        let button2 = alert.addButton(withTitle: "Shutdown")
        button2.keyEquivalent = "\r"

        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            return .terminateNow
        case .alertSecondButtonReturn:
            defer { shutdownAll() }
            
            return .terminateLater
        default:
            return .terminateCancel
        }
    }
}

// MARK: - Removable Volume Detection

/// External volume detection
extension VMLibraryController {
    /// `true` if the specified file URL lives in a removable volume that could be unmounted when the app attempts to access it.
    static func isLibraryURLInRemovableVolume(_ url: URL) -> Bool {
        if let isInRemovableVolume = url.isInRemovableVolume {
            isInRemovableVolume
        } else if url.path.hasPrefix("/Volumes") {
            /// Assume removable volume when path starts with `/Volumes`.
            /// This is technically wrong as an external volume can be mounted anywhere and the built-in data
            /// volume is also located in `/Volumes`, but that one will always be mounted when this is used.
            /// It's fine to do here because this is only meant to be used for reporting things in the UI.
            true
        } else {
            /// Settings stores the removable volume state of the library directory when the user customizes it,
            /// use that fact as the final response if above checks fail.
            /// This is needed because we could be checking a URL for a directory that doesn't currently exist,
            /// and the mount could be somewhere other than `/Volumes`, so we have to go with what we knew before.
            VBSettings.current.isLibraryInRemovableVolume
        }
    }
}

extension URL {
    /// Whether the file resides in a removable volume, or `nil` if it can't be determined.
    var isInRemovableVolume: Bool? {
        guard let volumeURL = try? resourceValues(forKeys: [.volumeURLKey]).volume else { return nil }
        return (try? volumeURL.resourceValues(forKeys: [.volumeIsRemovableKey]))?.volumeIsRemovable
    }
}

private extension VMLibraryController {
    func observeRemovableVolumeNotifications() {
        /// Only observe when library lives in a removable volume.
        guard isLibraryInRemovableVolume else { return }

        guard volumeNotificationsTask == nil || volumeNotificationsTask?.isCancelled == true else { return }

        logger.debug(#function)

        volumeNotificationsTask = Task.detached(priority: .background) { [weak self] in
            await withTaskGroup { group in
                group.addTask {
                    for await notification in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didMountNotification) {
                        guard !Task.isCancelled else { return }
                        await self?.handleVolumeNotification(notification)
                    }
                }

                group.addTask {
                    for await notification in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didUnmountNotification) {
                        guard !Task.isCancelled else { return }
                        await self?.handleVolumeNotification(notification)
                    }
                }
            }
        }
    }

    func stopObservingRemovableVolumeNotifications() {
        logger.debug(#function)

        volumeNotificationsTask?.cancel()
        volumeNotificationsTask = nil
    }

    func handleVolumeNotification(_ notification: Notification) {
        let isMount = notification.name == NSWorkspace.didMountNotification

        if isMount {
            /// Don't care about mount notifications unless we're currently waiting for the volume to mount.
            guard state.isVolumeNotMounted else { return }
        }

        guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }

        /// Cheap way to check if mounted volume is our library volume.
        guard libraryURL.path.hasPrefix(volumeURL.path) else { return }

        logger.notice("Library volume mounted: \(volumeURL.path.quoted)")

        /// Try to load machines again now that library is mounted.
        loadMachines()
    }
}

#if DEBUG
// MARK: - Debug State Simulation

private extension VMLibraryController {
    func simulateState() -> Bool {
        if UserDefaults.standard.bool(forKey: "VBSimulateLibraryVolumeNotMounted") {
            state = .volumeNotMounted
            return true
        } else if UserDefaults.standard.bool(forKey: "VBSimulateLibraryDirectoryMissing") {
            state = .directoryMissing
            return true
        } else if UserDefaults.standard.bool(forKey: "VBSimulateLibraryEmpty") {
            state = .empty
            return true
        } else {
            return false
        }
    }
}
#endif
