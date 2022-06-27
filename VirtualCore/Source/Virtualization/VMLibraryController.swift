//
//  VMLibraryController.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 10/04/22.
//

import Foundation
import Combine
import OSLog

@MainActor
public final class VMLibraryController: ObservableObject {

    public enum State {
        case loading
        case loaded([VBVirtualMachine])
        case failed(VBError)
    }
    
    @Published public private(set) var state = State.loading {
        didSet {
            if case .loaded(let vms) = state {
                self.virtualMachines = vms
            }
        }
    }
    
    @Published public private(set) var virtualMachines: [VBVirtualMachine] = []
    
    public static let shared = VMLibraryController()

    let settingsContainer: VBSettingsContainer

    private let filePresenter: VMLibraryFilePresenter
    private let updateSignal = PassthroughSubject<URL, Never>()

    init(settingsContainer: VBSettingsContainer = .current) {
        self.settingsContainer = settingsContainer
        self.settings = settingsContainer.settings
        self.libraryURL = settingsContainer.settings.libraryURL
        self.filePresenter = VMLibraryFilePresenter(
            presentedItemURL: settingsContainer.settings.libraryURL,
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
            loadMachines()
        }
    }

    private lazy var cancellables = Set<AnyCancellable>()
    
    private lazy var fileManager = FileManager()

    private func bind() {
        settingsContainer.$settings.sink { [weak self] newSettings in
            self?.settings = newSettings
        }
        .store(in: &cancellables)

        updateSignal
            .removeDuplicates()
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.loadMachines()
            }
            .store(in: &cancellables)
    }

    public func loadMachines() {
        filePresenter.presentedItemURL = libraryURL

        guard let enumerator = fileManager.enumerator(at: libraryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants], errorHandler: nil) else {
            state = .failed(.init("Failed to open directory at \(libraryURL.path)"))
            return
        }
        
        var vms = [VBVirtualMachine]()
        
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == VBVirtualMachine.bundleExtension else { continue }
            
            do {
                let machine = try VBVirtualMachine(bundleURL: url)
                
                vms.append(machine)
            } catch {
                assertionFailure("Failed to construct VM model: \(error)")
            }
        }
        
        self.state = .loaded(vms)
    }
    
}

private final class VMLibraryFilePresenter: NSObject, NSFilePresenter {

    private lazy var logger = Logger(for: Self.self)

    var presentedItemURL: URL?

    var presentedItemOperationQueue: OperationQueue = .main

    let signal: PassthroughSubject<URL, Never>

    init(presentedItemURL: URL?, signal: PassthroughSubject<URL, Never>) {
        self.presentedItemURL = presentedItemURL
        self.signal = signal

        super.init()

        NSFileCoordinator.addFilePresenter(self)
    }

    private func sendSignalIfNeeded(for url: URL) {
        guard url.pathExtension == VBVirtualMachine.bundleExtension else { return }

        signal.send(url)
    }

    func presentedSubitemDidAppear(at url: URL) {
        logger.debug("Added: \(url.path)")

        sendSignalIfNeeded(for: url)
    }

    func presentedSubitemDidChange(at url: URL) {
        logger.debug("Changed: \(url.path)")

        sendSignalIfNeeded(for: url)
    }

    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        logger.debug("Moved: \(oldURL.path) -> \(newURL.path)")

        sendSignalIfNeeded(for: newURL)
    }

    func accommodatePresentedSubitemDeletion(at url: URL) async throws {
        logger.debug("Deleted: \(url.path)")

        sendSignalIfNeeded(for: url)
    }

}

// MARK: - Download Helpers

public extension VMLibraryController {

    func getDownloadsBaseURL() throws -> URL {
        let baseURL = libraryURL.appendingPathComponent("_Downloads")
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }

        return baseURL
    }

    func existingLocalURL(for remoteURL: URL) throws -> URL? {
        let localURL = try getDownloadsBaseURL()

        let downloadedFileURL = localURL.appendingPathComponent(remoteURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: downloadedFileURL.path) {
            return downloadedFileURL
        } else {
            return nil
        }
    }

}
