//
//  VMSnapshotHoverOverlay.swift
//  VirtualUI
//
//  Created for VirtualBuddy VM snapshot hover functionality.
//

import SwiftUI
import VirtualCore
import AppKit
import UniformTypeIdentifiers

struct VMSnapshotHoverOverlay: View {
    @EnvironmentObject private var controller: VMController
    @State private var isHovered = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Invisible full coverage area for hover detection
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                
                if isHovered {
                    // Semi-transparent overlay
                    Rectangle()
                        .fill(Color.black.opacity(0.4))
                        .transition(.opacity)
                    
                    // Button container
                    VStack(spacing: 16) {
                        Spacer()
                        
                        HStack(spacing: 16) {
                            // Save Image button
                            Button {
                                saveScreenshotToHost()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Save Image")
                                }
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(OverlayButtonStyle())
                            
                            // Disable Preview button
                            Button {
                                toggleScreenshotGeneration()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: controller.virtualMachineModel.metadata.screenshotGenerationEnabled ? "eye.slash" : "eye")
                                    Text(controller.virtualMachineModel.metadata.screenshotGenerationEnabled ? "Disable Previews" : "Enable Previews")
                                }
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(OverlayButtonStyle())
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private func saveScreenshotToHost() {
        guard let screenshot = controller.virtualMachineModel.screenshot else {
            NSAlert.runInformationAlert(
                title: "No Screenshot Available",
                message: "There is no screenshot available for this virtual machine."
            )
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.title = "Save VM Screenshot"
        savePanel.nameFieldStringValue = "\(controller.virtualMachineModel.name) Screenshot"
        savePanel.allowedContentTypes = [.png, .jpeg, .heic]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            // Convert to the appropriate format based on file extension
            let fileExtension = url.pathExtension.lowercased()
            let success: Bool
            
            switch fileExtension {
            case "png":
                success = screenshot.pngWrite(to: url)
            case "jpg", "jpeg":
                success = screenshot.jpegWrite(to: url, compressionFactor: 0.9)
            case "heic":
                success = (try? screenshot.vb_encodeHEIC(to: url)) != nil
            default:
                // Default to PNG
                success = screenshot.pngWrite(to: url.appendingPathExtension("png"))
            }
            
            if !success {
                NSAlert.runErrorAlert(
                    title: "Save Failed",
                    message: "Failed to save the screenshot to \(url.path)."
                )
            }
        }
    }
    
    private func toggleScreenshotGeneration() {
        let currentlyEnabled = controller.virtualMachineModel.metadata.screenshotGenerationEnabled
        controller.virtualMachineModel.metadata.screenshotGenerationEnabled = !currentlyEnabled
        
        // Force save the metadata
        do {
            try controller.virtualMachineModel.saveMetadata()
        } catch {
            NSAlert.runErrorAlert(
                title: "Settings Save Failed",
                message: "Failed to save the screenshot generation setting: \(error.localizedDescription)"
            )
            // Revert the change
            controller.virtualMachineModel.metadata.screenshotGenerationEnabled = currentlyEnabled
        }
    }
}

// Custom button style for overlay buttons
private struct OverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Material.thick)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            )
            .foregroundColor(.primary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Extensions for NSImage saving
private extension NSImage {
    func pngWrite(to url: URL) -> Bool {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return false
        }
        
        do {
            try pngData.write(to: url)
            return true
        } catch {
            return false
        }
    }
    
    func jpegWrite(to url: URL, compressionFactor: CGFloat = 0.9) -> Bool {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor]) else {
            return false
        }
        
        do {
            try jpegData.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

// Extensions for NSAlert convenience
private extension NSAlert {
    static func runInformationAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    static func runErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

#if DEBUG
struct VMSnapshotHoverOverlay_Previews: PreviewProvider {
    static var previews: some View {
        VMSnapshotHoverOverlay()
            .environmentObject(VMController.preview)
            .frame(width: 400, height: 300)
            .background(Color.blue.opacity(0.3))
    }
}
#endif 