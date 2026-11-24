import Darwin
import Foundation
import MacDebugProtocol

extension DebugSocket {
    static func guestListener() throws -> (DebugSocket, UInt32) {
        let stream = try DebugSocket(owning: socket(AF_VSOCK, SOCK_STREAM, 0))
        var address = sockaddr_vm()
        address.svm_family = sa_family_t(AF_VSOCK)
        address.svm_len = UInt8(MemoryLayout<sockaddr_vm>.size)
        address.svm_port = UInt32(VMADDR_PORT_ANY)
        address.svm_cid = UInt32(VMADDR_CID_ANY)
        var size = socklen_t(address.svm_len)
        let ok = withUnsafeMutablePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(stream.descriptor, $0, size) == 0 && listen(stream.descriptor, 1) == 0 && getsockname(stream.descriptor, $0, &size) == 0
            }
        }
        guard ok else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        return (stream, address.svm_port)
    }

    func acceptDebuggerFromHost() async throws -> DebugSocket {
        try await accept(timeout: 90_000) { _, address in
            let isHost = withUnsafePointer(to: address) { pointer in
                pointer.withMemoryRebound(to: sockaddr_vm.self, capacity: 1) {
                    $0.pointee.svm_family == AF_VSOCK && $0.pointee.svm_cid == VMADDR_CID_HOST
                }
            }
            guard isHost else { throw POSIXError(.EACCES) }
        }
    }
}
