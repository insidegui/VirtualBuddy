//
//  WHSharedClipboardService.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import OSLog

final class WHSharedClipboardService: WormholeService {
    
    private lazy var logger = Logger(for: Self.self)
    
    static var contextID: Int { 1 }
    
    private var readHandle: FileHandle
    private var writeHandle: FileHandle
    
    init?(readHandle: FileHandle, writeHandle: FileHandle) {
        self.readHandle = readHandle
        self.writeHandle = writeHandle
    }
    
    func activate() {
        logger.debug(#function)
        
        runTask()
    }
    
    private func runTask() {
        Task { await fileHandleTask() }
    }
    
    private func fileHandleTask() async {
        logger.debug("Entering file handle task")
        
        do {
            for try await line in readHandle.bytes.lines {
                logger.debug("-> \(line)")
                
                await Task.yield()
            }
        } catch {
            logger.error("File handle task error: \(String(describing: error), privacy: .public)")
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            runTask()
        }
    }
    
}
