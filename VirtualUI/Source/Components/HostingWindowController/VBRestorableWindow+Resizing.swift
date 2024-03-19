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

        let targetWidth: CGFloat
        let targetHeight: CGFloat
        let displaySize = CGSize(width: display.width, height: display.height)
        let toolbarHeight: CGFloat = frameRect(forContentRect: NSRect()).height
        // screen.visibleFrame.height is a "net" value after taking into account menu bar, dock, etc.
        let availableHeight: CGFloat = screen.visibleFrame.height - toolbarHeight

        switch size {
        case .pointAccurate:
            targetWidth = CGFloat(display.width)
            targetHeight = CGFloat(display.height)
        case .pixelAccurate:
            targetWidth = CGFloat(display.width) / screen.backingScaleFactor
            targetHeight = CGFloat(display.height) / screen.backingScaleFactor
        case .fitScreen:
            let windowAspectRatio = displaySize.width / displaySize.height
            let containerAspectRatio = screen.visibleFrame.width / availableHeight
            let widthFirst = windowAspectRatio > containerAspectRatio

            if widthFirst {
                targetWidth = screen.visibleFrame.width
                targetHeight = targetWidth / windowAspectRatio
            } else {
                targetHeight = availableHeight
                targetWidth = availableHeight * windowAspectRatio
            }
        }

        // clamped targetSize to the available screen's real estate
        let targetSize = CGSize(
            width: min(targetWidth, screen.visibleFrame.width),
            height: min(targetHeight, availableHeight)
        )

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

        contentAspectRatio = ratio

        let newFrame = frameRect(forContentRect: AVMakeRect(aspectRatio: ratio, insideRect: contentRect(forFrameRect: frame)))

        setFrame(newFrame, display: true)
    }

}
