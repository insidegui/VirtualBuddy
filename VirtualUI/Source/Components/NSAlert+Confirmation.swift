//
//  NSAlert+Confirmation.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 29/06/22.
//

import Cocoa

public extension NSAlert {

    static func runConfirmationAlert(title: String,
                                     message: String,
                                     continueButtonTitle: String = "Continue",
                                     cancelButtonTitle: String = "Cancel",
                                     continueButtonIsDefault: Bool = false) async -> Bool
    {
        let alert = NSAlert()

        alert.messageText = title
        alert.informativeText = message

        if continueButtonIsDefault {
            alert.addButton(withTitle: continueButtonTitle)
            alert.addButton(withTitle: cancelButtonTitle)
        } else {
            alert.addButton(withTitle: cancelButtonTitle)
            alert.addButton(withTitle: continueButtonTitle)
        }

        let response: NSApplication.ModalResponse

        if let window = NSApp?.keyWindow {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }

        return continueButtonIsDefault ? response == .alertFirstButtonReturn : response == .alertSecondButtonReturn
    }

}
