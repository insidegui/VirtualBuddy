//
//  VBRestorableWindow+Resizing.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 09/03/23.
//

import Cocoa
import AVFoundation
import VirtualCore

extension VBRestorableWindow {

    func resize(to size: VirtualMachineSessionUI.WindowSize, for display: VBDisplayDevice) {
        guard let screen else { return }

        let targetSize: CGSize
        let displaySize = CGSize(width: display.width, height: display.height)
        let availableHeight: CGFloat = screen.visibleFrame.height - screen.visibleFrame.origin.y / 2

        switch size {
        case .pointAccurate:
            targetSize = CGSize(
                width: CGFloat(display.width) * 72.0 / CGFloat(display.pixelsPerInch),
                height: CGFloat(display.height) * 72.0 / CGFloat(display.pixelsPerInch)
            )
        case .pixelAccurate:
            targetSize = CGSize(
                width: CGFloat(display.width) * screen.dpi.width / CGFloat(display.pixelsPerInch),
                height: CGFloat(display.height) * screen.dpi.height / CGFloat(display.pixelsPerInch)
            )
        case .fitScreen:
            let windowAspectRatio = displaySize.width / displaySize.height
            let containerAspectRatio = screen.visibleFrame.width / availableHeight
            let widthFirst = windowAspectRatio > containerAspectRatio

            let windowWidth: CGFloat
            let windowHeight: CGFloat

            if widthFirst {
                windowWidth = screen.visibleFrame.width
                windowHeight = windowWidth / windowAspectRatio
            } else {
                windowHeight = availableHeight
                windowWidth = windowHeight * windowAspectRatio
            }

            targetSize = CGSize(width: windowWidth, height: windowHeight)
        }

        let targetRect = NSRect(
            x: screen.visibleFrame.origin.x + screen.visibleFrame.width / 2 - targetSize.width / 2,
            y: screen.visibleFrame.origin.y + availableHeight / 2 - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )

        let frameRect = frameRect(forContentRect: targetRect)

        withFrameConstraintsDisabled(size != .fitScreen) {
            setFrame(frameRect, display: true)
        }
    }

    func applyAspectRatio(_ ratio: CGSize?) {
        guard let ratio else {
            resizeIncrements = CGSize(width: 1, height: 1)
            return
        }

        aspectRatio = ratio

        let newFrame = frameRect(forContentRect: AVMakeRect(aspectRatio: ratio, insideRect: frame))

        setFrame(newFrame, display: true)
    }

}

extension NSScreen {
    var dpi: CGSize {
        (deviceDescription[NSDeviceDescriptionKey.resolution] as? CGSize) ?? CGSize(width: 72.0, height: 72.0)
    }
}
