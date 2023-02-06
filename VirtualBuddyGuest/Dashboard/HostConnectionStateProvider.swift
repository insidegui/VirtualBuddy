import Foundation
import VirtualWormhole

protocol HostConnectionStateProvider: ObservableObject {
    var isConnected: Bool { get }
}

extension WormholeManager: HostConnectionStateProvider { }
