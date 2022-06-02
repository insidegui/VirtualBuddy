//
//  WormholeServiceProtocol.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import Virtualization

protocol WormholeService: AnyObject {
    
    static var contextID: Int { get }
    
    init?(readHandle: FileHandle, writeHandle: FileHandle)
    
    func activate()
    
}
