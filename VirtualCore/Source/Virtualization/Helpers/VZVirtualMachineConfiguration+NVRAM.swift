//
//  VZVirtualMachineConfiguration+NVRAM.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 11/04/22.
//

import Foundation
import Virtualization

public struct Failure: LocalizedError {
    public var errorDescription: String?
    
    public init(_ msg: String) { self.errorDescription = msg }
}

public extension VZMacAuxiliaryStorage {

    func fetchNVRAMVariables() throws -> [VBNVRAMVariable] {
        var error: NSError?
        let variables = _allNVRAMVariablesWithError(&error)
        
        if let error = error { throw error }
        
        let vars = variables.map { VBNVRAMVariable(name: $0.key, value: $0.value as? String) }
        return vars
    }
    
    func updateNVRAM(_ variable: VBNVRAMVariable) throws {
        if let value = variable.value {
            try _setValue(value, forNVRAMVariableNamed: variable.name)
        } else {
            try _removeNVRAMVariableNamed(variable.name)
        }
    }
    
}

#if DEBUG
public extension VBMacConfiguration {
    static var nvramEditorPreview: VBMacConfiguration {
        let storage = VZMacAuxiliaryStorage(contentsOf: URL(fileURLWithPath: "/Users/insidegui/Downloads/AuxiliaryStorage"))
        let variables = try! storage.fetchNVRAMVariables()
        var config = VBVirtualMachine.preview.configuration
        var device = config.hardware
        device.NVRAM = variables
        config.hardware = device
        return config
    }
}
#endif
