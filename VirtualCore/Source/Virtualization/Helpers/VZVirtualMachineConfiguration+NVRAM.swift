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
    
    init(_ msg: String) { self.errorDescription = msg }
}

public extension VZVirtualMachineConfiguration {
    
    internal var macStorage: VZMacAuxiliaryStorage {
        get throws {
            guard let storage = (platform as? VZMacPlatformConfiguration)?.auxiliaryStorage else {
                throw Failure("This VM doesn't have storage for NVRAM variables")
            }
            
            return storage
        }
    }
    
    func fetchNVRAMVariables() throws -> [VBNVRAMVariable] {
        var error: NSError?
        let variables = try macStorage._allNVRAMVariablesWithError(&error)
        
        if let error = error { throw error }
        
        let vars = variables.map { VBNVRAMVariable(name: $0.key, value: $0.value as? String) }
        return vars
    }
    
    func updateNVRAM(_ variable: VBNVRAMVariable) throws {
        let storage = try macStorage
        
        if let value = variable.value {
            try storage._setValue(value, forNVRAMVariableNamed: variable.name)
        } else {
            try storage._removeNVRAMVariableNamed(variable.name)
        }
    }
    
}
