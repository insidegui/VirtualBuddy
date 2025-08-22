//
//  VBDiskResizer.swift
//  VirtualCore
//
//  Created by VirtualBuddy on 22/08/25.
//

import Foundation

public enum VBDiskResizeError: LocalizedError {
    case diskImageNotFound(URL)
    case unsupportedImageFormat(VBManagedDiskImage.Format)
    case insufficientSpace(required: UInt64, available: UInt64)
    case cannotShrinkDisk
    case systemCommandFailed(String, Int32)
    case invalidSize(UInt64)
    
    public var errorDescription: String? {
        switch self {
        case .diskImageNotFound(let url):
            return "Disk image not found at path: \(url.path)"
        case .unsupportedImageFormat(let format):
            return "Resizing is not supported for \(format.displayName) format"
        case .insufficientSpace(let required, let available):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let requiredStr = formatter.string(fromByteCount: Int64(required))
            let availableStr = formatter.string(fromByteCount: Int64(available))
            return "Insufficient disk space. Required: \(requiredStr), Available: \(availableStr)"
        case .cannotShrinkDisk:
            return "Cannot shrink disk image. Only expansion is supported for safety reasons."
        case .systemCommandFailed(let command, let exitCode):
            return "System command '\(command)' failed with exit code \(exitCode)"
        case .invalidSize(let size):
            return "Invalid size: \(size) bytes. Size must be larger than current disk size."
        }
    }
}

public struct VBDiskResizer {
    
    public enum ResizeStrategy {
        case createLargerImage
        case expandInPlace
    }
    
    public static func canResizeFormat(_ format: VBManagedDiskImage.Format) -> Bool {
        switch format {
        case .raw, .dmg, .sparse:
            return true
        case .asif:
            return false
        }
    }
    
    public static func recommendedStrategy(for format: VBManagedDiskImage.Format) -> ResizeStrategy {
        switch format {
        case .raw:
            return .createLargerImage
        case .dmg, .sparse:
            return .expandInPlace
        case .asif:
            return .createLargerImage
        }
    }
    
    public static func resizeDiskImage(
        at url: URL,
        format: VBManagedDiskImage.Format,
        newSize: UInt64,
        strategy: ResizeStrategy? = nil
    ) async throws {
        guard canResizeFormat(format) else {
            throw VBDiskResizeError.unsupportedImageFormat(format)
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VBDiskResizeError.diskImageNotFound(url)
        }
        
        let currentSize = try await getCurrentImageSize(at: url, format: format)
        guard newSize > currentSize else {
            throw VBDiskResizeError.cannotShrinkDisk
        }
        
        let finalStrategy = strategy ?? recommendedStrategy(for: format)
        
        switch finalStrategy {
        case .createLargerImage:
            try await createLargerImage(at: url, format: format, newSize: newSize, currentSize: currentSize)
        case .expandInPlace:
            try await expandImageInPlace(at: url, format: format, newSize: newSize)
        }
        
        // After resizing the disk image, attempt to expand the partition
        try await expandPartitionsInDiskImage(at: url, format: format)
    }
    
    private static func getCurrentImageSize(at url: URL, format: VBManagedDiskImage.Format) async throws -> UInt64 {
        switch format {
        case .raw:
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? UInt64 ?? 0
            
        case .dmg, .sparse:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["imageinfo", "-plist", url.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                throw VBDiskResizeError.systemCommandFailed("hdiutil imageinfo", process.terminationStatus)
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let size = plist["Total Bytes"] as? UInt64 else {
                throw VBDiskResizeError.systemCommandFailed("hdiutil imageinfo", -1)
            }
            
            return size
            
        case .asif:
            throw VBDiskResizeError.unsupportedImageFormat(format)
        }
    }
    
    private static func createLargerImage(
        at url: URL,
        format: VBManagedDiskImage.Format,
        newSize: UInt64,
        currentSize: UInt64
    ) async throws {
        let backupURL = url.appendingPathExtension("backup")
        let tempURL = url.appendingPathExtension("resizing")
        
        let parentDir = url.deletingLastPathComponent()
        let availableSpace = try await getAvailableSpace(at: parentDir)
        
        let requiredSpace = newSize + currentSize
        guard availableSpace >= requiredSpace else {
            throw VBDiskResizeError.insufficientSpace(required: requiredSpace, available: availableSpace)
        }
        
        do {
            try FileManager.default.moveItem(at: url, to: backupURL)
            
            switch format {
            case .raw:
                // Create empty file of new size
                FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
                let fileHandle = try FileHandle(forWritingTo: tempURL)
                defer { fileHandle.closeFile() }
                
                let result = ftruncate(fileHandle.fileDescriptor, Int64(newSize))
                guard result == 0 else {
                    throw VBDiskResizeError.systemCommandFailed("ftruncate", result)
                }
                
                // Copy original data to the beginning of the new larger file
                let sourceFile = try FileHandle(forReadingFrom: backupURL)
                fileHandle.seek(toFileOffset: 0)
                defer { sourceFile.closeFile() }
                
                let bufferSize = 1024 * 1024
                while true {
                    let data = sourceFile.readData(ofLength: bufferSize)
                    if data.isEmpty { break }
                    fileHandle.write(data)
                }
                
            case .dmg, .sparse:
                try await createExpandedDMGImage(from: backupURL, to: tempURL, newSize: newSize, format: format)
                
            case .asif:
                throw VBDiskResizeError.unsupportedImageFormat(format)
            }
            
            try FileManager.default.moveItem(at: tempURL, to: url)
            try FileManager.default.removeItem(at: backupURL)
            
        } catch {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.moveItem(at: backupURL, to: url)
            }
            
            throw error
        }
    }
    
    private static func expandImageInPlace(at url: URL, format: VBManagedDiskImage.Format, newSize: UInt64) async throws {
        let parentDir = url.deletingLastPathComponent()
        let availableSpace = try await getAvailableSpace(at: parentDir)
        
        guard availableSpace >= newSize else {
            throw VBDiskResizeError.insufficientSpace(required: newSize, available: availableSpace)
        }
        
        switch format {
        case .dmg, .sparse:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            
            let sizeInSectors = newSize / 512
            process.arguments = ["resize", "-size", "\(sizeInSectors)s", url.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw VBDiskResizeError.systemCommandFailed("hdiutil resize: \(errorString)", process.terminationStatus)
            }
            
        case .raw:
            try await expandRawImageInPlace(at: url, newSize: newSize)
            
        case .asif:
            throw VBDiskResizeError.unsupportedImageFormat(format)
        }
    }
    
    private static func createRawImage(at url: URL, size: UInt64) async throws {
        let tempURL = url.appendingPathExtension("tmp")
        
        // Create the temporary file first
        FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
        
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        defer { fileHandle.closeFile() }
        
        let result = ftruncate(fileHandle.fileDescriptor, Int64(size))
        guard result == 0 else {
            throw VBDiskResizeError.systemCommandFailed("ftruncate", result)
        }
        
        try FileManager.default.moveItem(at: tempURL, to: url)
    }
    
    private static func createExpandedDMGImage(from sourceURL: URL, to destURL: URL, newSize: UInt64, format: VBManagedDiskImage.Format) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        
        let formatArg: String
        switch format {
        case .dmg:
            formatArg = "UDRW"
        case .sparse:
            formatArg = "SPARSE"
        default:
            formatArg = "UDRW"
        }
        
        let sizeInSectors = newSize / 512
        process.arguments = [
            "convert", sourceURL.path,
            "-format", formatArg,
            "-o", destURL.path,
            "-size", "\(sizeInSectors)s"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw VBDiskResizeError.systemCommandFailed("hdiutil convert: \(errorString)", process.terminationStatus)
        }
    }
    
    private static func expandRawImageInPlace(at url: URL, newSize: UInt64) async throws {
        let fileHandle = try FileHandle(forWritingTo: url)
        defer { fileHandle.closeFile() }
        
        let result = ftruncate(fileHandle.fileDescriptor, Int64(newSize))
        guard result == 0 else {
            throw VBDiskResizeError.systemCommandFailed("ftruncate", result)
        }
    }
    
    private static func getAvailableSpace(at url: URL) async throws -> UInt64 {
        let resourceValues = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return UInt64(resourceValues.volumeAvailableCapacity ?? 0)
    }
    
    /// Expands partitions within a disk image to use the newly available space
    private static func expandPartitionsInDiskImage(at url: URL, format: VBManagedDiskImage.Format) async throws {
        NSLog("Attempting to expand partitions in disk image at \(url.path)")
        
        switch format {
        case .raw:
            // For RAW images, we need to mount and resize using diskutil
            try await expandPartitionsInRawImage(at: url)
            
        case .dmg, .sparse:
            // For DMG/Sparse images, we can work with them directly
            try await expandPartitionsInDMGImage(at: url)
            
        case .asif:
            // ASIF format doesn't support resizing
            NSLog("Skipping partition expansion for ASIF format")
        }
    }
    
    private static func expandPartitionsInRawImage(at url: URL) async throws {
        // Mount the disk image as a device
        let attachProcess = Process()
        attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProcess.arguments = ["attach", "-imagekey", "diskimage-class=CRawDiskImage", "-nomount", url.path]
        
        let attachPipe = Pipe()
        attachProcess.standardOutput = attachPipe
        attachProcess.standardError = Pipe()
        
        try attachProcess.run()
        attachProcess.waitUntilExit()
        
        guard attachProcess.terminationStatus == 0 else {
            throw VBDiskResizeError.systemCommandFailed("hdiutil attach", attachProcess.terminationStatus)
        }
        
        let attachOutput = String(data: attachPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        // Extract device node (e.g., /dev/disk4)
        guard let deviceNode = extractDeviceNode(from: attachOutput) else {
            throw VBDiskResizeError.systemCommandFailed("Could not extract device node", -1)
        }
        
        defer {
            // Detach the disk image when done
            let detachProcess = Process()
            detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detachProcess.arguments = ["detach", deviceNode]
            try? detachProcess.run()
            detachProcess.waitUntilExit()
        }
        
        // Resize the partition using diskutil
        try await resizePartitionOnDevice(deviceNode: deviceNode)
    }
    
    private static func expandPartitionsInDMGImage(at url: URL) async throws {
        // Mount the DMG and resize its partitions
        let attachProcess = Process()
        attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProcess.arguments = ["attach", "-nomount", url.path]
        
        let attachPipe = Pipe()
        attachProcess.standardOutput = attachPipe
        attachProcess.standardError = Pipe()
        
        try attachProcess.run()
        attachProcess.waitUntilExit()
        
        guard attachProcess.terminationStatus == 0 else {
            throw VBDiskResizeError.systemCommandFailed("hdiutil attach", attachProcess.terminationStatus)
        }
        
        let attachOutput = String(data: attachPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        guard let deviceNode = extractDeviceNode(from: attachOutput) else {
            throw VBDiskResizeError.systemCommandFailed("Could not extract device node", -1)
        }
        
        defer {
            let detachProcess = Process()
            detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detachProcess.arguments = ["detach", deviceNode]
            try? detachProcess.run()
            detachProcess.waitUntilExit()
        }
        
        try await resizePartitionOnDevice(deviceNode: deviceNode)
    }
    
    private static func extractDeviceNode(from hdiutilOutput: String) -> String? {
        // hdiutil output format: "/dev/disk4          	Apple_partition_scheme"
        let lines = hdiutilOutput.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("/dev/disk") {
                let components = line.components(separatedBy: .whitespaces)
                if let deviceNode = components.first, deviceNode.hasPrefix("/dev/disk") {
                    return deviceNode
                }
            }
        }
        return nil
    }
    
    private static func resizePartitionOnDevice(deviceNode: String) async throws {
        NSLog("Attempting to resize partition on device \(deviceNode)")
        
        // First, get partition information
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        listProcess.arguments = ["list", deviceNode]
        
        let listPipe = Pipe()
        listProcess.standardOutput = listPipe
        listProcess.standardError = Pipe()
        
        try listProcess.run()
        listProcess.waitUntilExit()
        
        guard listProcess.terminationStatus == 0 else {
            NSLog("Warning: Could not list partitions on \(deviceNode)")
            return
        }
        
        let listOutput = String(data: listPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        // Find the main partition (usually s2 for APFS/HFS+ on macOS VMs)
        guard let partitionIdentifier = findResizablePartition(in: listOutput, deviceNode: deviceNode) else {
            NSLog("Warning: Could not find resizable partition on \(deviceNode)")
            return
        }
        
        NSLog("Found resizable partition: \(partitionIdentifier)")
        
        // Resize the partition to use all available space
        let resizeProcess = Process()
        resizeProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        resizeProcess.arguments = ["resizeVolume", partitionIdentifier, "R"]
        
        let resizePipe = Pipe()
        resizeProcess.standardOutput = resizePipe
        resizeProcess.standardError = resizePipe
        
        try resizeProcess.run()
        resizeProcess.waitUntilExit()
        
        let resizeOutput = String(data: resizePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        if resizeProcess.terminationStatus == 0 {
            NSLog("Successfully expanded partition \(partitionIdentifier)")
        } else {
            NSLog("Warning: Failed to resize partition \(partitionIdentifier): \(resizeOutput)")
            // Don't throw an error here - the disk resize succeeded, partition resize is bonus
        }
    }
    
    private static func findResizablePartition(in diskutilOutput: String, deviceNode: String) -> String? {
        let lines = diskutilOutput.components(separatedBy: .newlines)
        
        // Look for APFS or HFS+ partitions (typically the main data partition)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip header and empty lines
            guard !trimmed.isEmpty && !trimmed.contains("TYPE NAME") else { continue }
            
            // Look for APFS Container or HFS+ partition
            if (trimmed.contains("APFS") || trimmed.contains("Apple_HFS")) && 
               (trimmed.contains("Container") || trimmed.contains("Macintosh HD") || trimmed.contains("disk")) {
                
                // Extract partition number (e.g., "1:" -> "disk4s1")
                let components = trimmed.components(separatedBy: .whitespaces)
                for component in components {
                    if component.hasSuffix(":") {
                        let partitionNum = component.dropLast() // Remove ":"
                        return "\(deviceNode)s\(partitionNum)"
                    }
                }
            }
        }
        
        // Fallback: try s2 which is commonly the main partition
        return "\(deviceNode)s2"
    }
}