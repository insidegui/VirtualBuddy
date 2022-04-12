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
        
//        NotificationCenter.default.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: nil, queue: nil) { note in
//            guard let window = note.object as? NSWindow else { return }
//            print(window)
//        }
    }
    
    @objc func restoreDefaultWindowPosition(_ sender: Any?) {
        guard let window = NSApp?.keyWindow ?? NSApp?.mainWindow else { return }
        
        window.setFrame(.init(x: 0, y: 0, width: 960, height: 600), display: true, animate: false)
        window.center()
    }
    
}
