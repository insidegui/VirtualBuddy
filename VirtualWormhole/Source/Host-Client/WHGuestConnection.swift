import Foundation
import Combine

protocol WHGuestConnection: AnyObject {
    func connect(using fileDescriptor: Int32, invalidationHandler: @escaping (Self) -> Void) async throws
    
    var packets: AnyPublisher<WormholePacket, Never> { get }

    func send(_ packet: WormholePacket) async throws
}
