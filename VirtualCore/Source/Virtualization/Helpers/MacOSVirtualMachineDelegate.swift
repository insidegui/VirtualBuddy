/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A class that conforms to `VZVirtualMachineDelegate` and to track the virtual machine's state.
*/

import Foundation
import Virtualization

class MacOSVirtualMachineDelegate: NSObject, VZVirtualMachineDelegate {
    
    let onVMStop: (Error?) -> Void
    
    init(onVMStop: @escaping (Error?) -> Void) {
        self.onVMStop = onVMStop
        
        super.init()
    }
    
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onVMStop(error) }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        DispatchQueue.main.async { self.onVMStop(nil) }
    }
}
