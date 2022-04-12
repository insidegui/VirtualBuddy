//
//  VBNVRAMVariable.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 11/04/22.
//

import Foundation

public struct VBNVRAMVariable: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public var value: String?
    
    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }
}
