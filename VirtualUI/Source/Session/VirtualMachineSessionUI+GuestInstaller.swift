import AppKit
import UniformTypeIdentifiers

@MainActor
extension VirtualMachineSessionUI {
    func exportGuestInstaller() {
        controller.guestInstallerExport.start(chooseDestination: { [self] in
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.diskImage]
            panel.nameFieldStringValue = "VirtualBuddyGuest-Update.dmg"
            panel.message = "Choose a shared folder that you can open inside the virtual machine."

            let response: NSApplication.ModalResponse
            if let hostWindow {
                response = await panel.beginSheetModal(for: hostWindow)
            } else {
                response = await panel.begin()
            }
            return response == .OK ? panel.url : nil
        }, export: controller.exportGuestInstaller, completion: { [self] result in
            switch result {
            case .success(let url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let error):
                let alert = NSAlert(error: error)
                alert.messageText = "Guest Installer Export Failed"
                if let hostWindow, hostWindow.isVisible {
                    alert.beginSheetModal(for: hostWindow)
                } else {
                    alert.runModal()
                }
            }
        })
    }
}
