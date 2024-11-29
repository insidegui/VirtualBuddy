import Foundation
import VirtualCore

protocol HostConnectionStateProvider: ObservableObject {
    @MainActor var hasConnection: Bool { get }
}

extension VMChannel: HostConnectionStateProvider {

}
