import Cocoa
import Virtualization

@available(macOS 14.0, *)
public extension NSImage {
    @MainActor
    static func screenshot(from virtualMachine: VZVirtualMachine) async throws -> NSImage {
        guard #unavailable(macOS 15.4) else {
            throw Failure("Feature disabled on macOS 15.4+")
        }
        guard let device = virtualMachine.graphicsDevices.first else {
            throw Failure("Can't screenshot a virtual machine without a graphics device.")
        }
        guard let display = device.displays.first else {
            throw Failure("Can't screenshot a virtual machine without a display.")
        }

        return try await screenshot(from: display)
    }

    @MainActor
    static func screenshot(from display: VZGraphicsDisplay) async throws -> NSImage {
        try await display.vb_takeScreenshot()
    }
}
