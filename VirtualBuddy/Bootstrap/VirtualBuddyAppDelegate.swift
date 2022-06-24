//
//  VirtualBuddyNSApp.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import Cocoa

@objc final class VirtualBuddyAppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp?.appearance = NSAppearance(named: .darkAqua)
    }
    
    @objc func restoreDefaultWindowPosition(_ sender: Any?) {
        guard let window = NSApp?.keyWindow ?? NSApp?.mainWindow else { return }
        
        window.setFrame(.init(x: 0, y: 0, width: 960, height: 600), display: true, animate: false)
        window.center()
    }
    
}
