//
//  VMLibraryController.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 10/04/22.
//

import Foundation
import Combine

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

    init(settingsContainer: VBSettingsContainer = .current) {
        self.settingsContainer = settingsContainer
        self.settings = settingsContainer.settings
        self.libraryURL = settingsContainer.settings.libraryURL

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
    }

    public func loadMachines() {
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
    
    private func metadataDirectoryCreatingIfNeeded(for machine: VBVirtualMachine) throws -> URL {
        let baseURL = machine.metadataDirectoryURL
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
        return baseURL
    }
    
    func write(_ data: Data, forMetadataFileNamed name: String, in machine: VBVirtualMachine) throws {
        let baseURL = try metadataDirectoryCreatingIfNeeded(for: machine)
        
        let fileURL = baseURL.appendingPathComponent(name)
        
        try data.write(to: fileURL, options: .atomic)
    }
    
    public func metadataContents(_ fileName: String, in machine: VBVirtualMachine) -> Data? {
        guard let baseURL = try? metadataDirectoryCreatingIfNeeded(for: machine) else { return nil }
        
        let fileURL = baseURL.appendingPathComponent(fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        return try? Data(contentsOf: fileURL)
    }
    
}
