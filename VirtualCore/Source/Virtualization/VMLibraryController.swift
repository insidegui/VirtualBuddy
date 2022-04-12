//
//  VMLibraryController.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 10/04/22.
//

import Foundation

public final class VMLibraryController: ObservableObject {
    
    public enum State {
        case loading
        case loaded([VBVirtualMachine])
        case failed(VBError)
    }
    
    @Published public private(set) var state = State.loading
    
    private var virtualMachines: [VBVirtualMachine] = []
    
    public init() {
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
    
}
