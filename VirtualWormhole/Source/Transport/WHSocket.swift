//
//  WHSocket.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 25/10/23.
//

import Foundation
import Virtualization

final class WHSocket {
    struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ errorDescription: String) {
            self.errorDescription = errorDescription
        }
    }
    
    private let fileDescriptor: Int32
    private let handle: FileHandle
    private let connection: VZVirtioSocketConnection?

    var bytes: FileHandle.AsyncBytes { handle.bytes }

    func write(_ data: Data) throws {  try handle.write(contentsOf: data) }

    init(fileDescriptor: Int32, connection: VZVirtioSocketConnection? = nil) {
        self.fileDescriptor = fileDescriptor
        self.handle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: connection == nil)
        self.connection = connection
    }

    deinit {
        if let connection { connection.close() }
    }
}

extension WHSocket {
    convenience init(connection: VZVirtioSocketConnection) {
        self.init(
            fileDescriptor: connection.fileDescriptor,
            connection: connection
        )
    }

    /// Instantiates a socket for the specified port between the guest (local machine) and the host.
    /// The host must have created a socket listener on the specified port.
    convenience init(hostPort: UInt32) throws {
        let descriptor = Darwin.socket(AF_VSOCK, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure("Failed to create socket file descriptor.")}

        let addr: sockaddr_vm = {
            var a = sockaddr_vm()
            a.svm_family = sa_family_t(AF_VSOCK)
            a.svm_port = hostPort
            a.svm_cid = UInt32(VMADDR_CID_HOST)
            return a
        }()

        try withUnsafeBytes(of: addr) { ptr in
            let addrPtr = ptr.assumingMemoryBound(to: sockaddr.self)
            guard let baseAddress = addrPtr.baseAddress else {
                throw Failure("Memory read failure.")
            }
            let result = Darwin.connect(descriptor, baseAddress, socklen_t(MemoryLayout<sockaddr_vm>.size))
            if result != 0 {
                throw Failure("Socket connection failed with code \(result).")
            }
        }

        self.init(fileDescriptor: descriptor)
    }
}
