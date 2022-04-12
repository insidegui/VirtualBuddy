//
//  VMLibraryController.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 10/04/22.
//

import Foundation

@MainActor
public final class VMLibraryController: ObservableObject {
    
    public enum State {
        case loading
        case loaded([VBVirtualMachine])
        case failed(VBError)
    }
    
    @Published public private(set) var state = State.loading
    
    private var virtualMachines: [VBVirtualMachine] = []
    
    public static let shared = VMLibraryController()
    
    init() {
        loadMachines()
    }
    
    private lazy var fileManager = FileManager()
    
    private lazy var libraryURL: URL = {
        (try! fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            .appendingPathComponent("VirtualBuddy")
    }()
    
    private func loadMachines() {
        guard let enumerator = fileManager.enumerator(at: libraryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants], errorHandler: nil) else {
            state = .failed(.init("Failed to open directory at \(libraryURL.path)"))
            return
        }
        
        var vms = [VBVirtualMachine]()
        
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == VBVirtualMachine.bundleExtension else { continue }
            
            vms.append(VBVirtualMachine(bundleURL: url))
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
    
    func write(_ data: Data, forMetadataFileNamed name: String, in machine: VBVirtualMachine) async throws {
        let baseURL = try metadataDirectoryCreatingIfNeeded(for: machine)
        
        let fileURL = baseURL.appendingPathComponent(name)
        
        try data.write(to: fileURL, options: .atomic)
    }
    
}
