#if DEBUG
import SwiftUI
import VirtualCore

@MainActor
public extension VirtualMachineSessionUI {
    static let preview = VirtualMachineSessionUI(controller: .preview)
}
#endif
