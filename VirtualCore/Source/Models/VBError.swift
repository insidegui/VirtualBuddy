//
//  VBError.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 10/04/22.
//

import Foundation

public struct VBError: LocalizedError {
    
    public var errorDescription: String?
    
    init(_ desc: String) { self.errorDescription = desc }
    
}
