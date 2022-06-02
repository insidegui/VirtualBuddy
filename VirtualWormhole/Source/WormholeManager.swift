//
//  WormholeManager.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import Virtualization
import OSLog

public final class WormholeManager: NSObject {
    
    private lazy var logger = Logger(for: Self.self)
    
    weak var vm: VZVirtualMachine!
    
//    private var device: VZVirtioSocketDevice
    
    let serviceTypes: [WormholeService.Type] = [
        WHSharedClipboardService.self
    ]
    
    var activeServices: [WormholeService] = []
    
    let fileHandleForReading: FileHandle
    let fileHandleForWriting: FileHandle
    
    public init?(with vm: VZVirtualMachine, fileHandleForReading: FileHandle, fileHandleForWriting: FileHandle) {
        self.fileHandleForReading = fileHandleForReading
        self.fileHandleForWriting = fileHandleForWriting
        self.vm = vm

        super.init()
        
//        listener = VZVirtioSocketListener()
//        listener.delegate = self
//        
//        for service in serviceTypes {
//            device.setSocketListener(listener, forPort: service.portNumber)
//            
//            logger.debug("Registered \(String(describing: service), privacy: .public) on port \(service.portNumber, privacy: .public)")
//        }
        
        for serviceType in serviceTypes {
            guard let service = serviceType.init(readHandle: fileHandleForReading, writeHandle: fileHandleForWriting) else {
                logger.error("Failed to initialize service: \(String(describing: serviceType), privacy: .public)")
                continue
            }
            
            service.activate()
            
            activeServices.append(service)
            
            logger.debug("Registered \(String(describing: service), privacy: .public) with context ID \(serviceType.contextID, privacy: .public)")
        }
        
        logger.debug("Initialized for \(String(describing: vm), privacy: .public)")
    }
    
}

//extension WormholeManager: VZVirtioSocketListenerDelegate {
//
//    public func listener(_ listener: VZVirtioSocketListener, shouldAcceptNewConnection connection: VZVirtioSocketConnection, from socketDevice: VZVirtioSocketDevice) -> Bool {
//        logger.debug("shouldAcceptNewConnection (source = \(connection.sourcePort), destination = \(connection.destinationPort))")
//
//        let servicePort = connection.destinationPort
//
//        guard let serviceType = serviceTypes.first(where: { $0.portNumber == servicePort }) else {
//            logger.error("Couldn't find a registered service for port number \(servicePort)")
//            return false
//        }
//
//        guard let service = serviceType.init(with: connection) else {
//            logger.error("\(String(describing: serviceType), privacy: .public) failed to instantiate for port \(servicePort)")
//            return false
//        }
//
//        activeServices.append(service)
//
//        service.activate()
//
//        return true
//    }
//
//}
