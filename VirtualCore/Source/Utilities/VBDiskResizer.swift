//
//  VBDiskResizer.swift
//  VirtualCore
//
//  Created by VirtualBuddy on 22/08/25.
//

import Foundation
import zlib

public enum VBDiskResizeError: LocalizedError {
    case diskImageNotFound(URL)
    case unsupportedImageFormat(VBManagedDiskImage.Format)
    case insufficientSpace(required: UInt64, available: UInt64)
    case cannotShrinkDisk
    case systemCommandFailed(String, Int32)
    case invalidSize(UInt64)
    case apfsVolumesLocked(container: String)

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
        case .apfsVolumesLocked(let container):
            return "The APFS container \(container) contains locked volumes. Unlock the disk (for example by signing into the FileVault-protected guest) and run 'diskutil apfs resizeContainer disk0s2 0' inside the guest to complete the resize."
        }
    }
}

private extension FileHandle {
    func vbWriteAll(_ data: Data) throws {
        if #available(macOS 10.15.4, *) {
            try self.write(contentsOf: data)
        } else {
            self.write(data)
        }
    }

    func vbRead(upToCount count: Int) throws -> Data? {
        if #available(macOS 10.15.4, *) {
            return try self.read(upToCount: count)
        } else {
            return self.readData(ofLength: count)
        }
    }

    func vbSeek(to offset: UInt64) throws {
        if #available(macOS 10.15.4, *) {
            _ = try self.seek(toOffset: offset)
        } else {
            self.seek(toFileOffset: offset)
        }
    }

    func vbSynchronize() throws {
        if #available(macOS 10.15.4, *) {
            try self.synchronize()
        } else {
            self.synchronizeFile()
        }
    }
}

public struct VBDiskResizer {
    
    public enum ResizeStrategy {
        case createLargerImage
        case expandInPlace
    }

    private struct APFSContainerInfo {
        let container: String
        let physicalStore: String?
        let hasLockedVolumes: Bool
    }

    private struct APFSContainerDetails {
        let capacityCeiling: UInt64
        let physicalStoreSize: UInt64
    }

    private static func sanitizeDeviceIdentifier(_ identifier: String) -> String {
        if identifier.hasPrefix("/dev/") {
            return String(identifier.dropFirst(5))
        }
        return identifier
    }

    public static func canResizeFormat(_ format: VBManagedDiskImage.Format) -> Bool {
        switch format {
        case .raw, .dmg, .sparse:
            return true
        case .asif:
            return false
        }
    }

    /// Checks if a disk image has FileVault (locked volumes) enabled.
    /// This attaches the disk image temporarily to inspect its APFS containers.
    /// - Parameters:
    ///   - url: The URL of the disk image to check.
    ///   - format: The format of the disk image.
    /// - Returns: `true` if the disk image has FileVault-protected (locked) volumes, `false` otherwise.
    public static func checkFileVaultStatus(at url: URL, format: VBManagedDiskImage.Format) async -> Bool {
        guard canResizeFormat(format) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        // Attach the disk image without mounting
        let attachProcess = Process()
        attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")

        switch format {
        case .raw:
            attachProcess.arguments = ["attach", "-imagekey", "diskimage-class=CRawDiskImage", "-nomount", url.path]
        case .dmg, .sparse:
            attachProcess.arguments = ["attach", "-nomount", url.path]
        case .asif:
            return false
        }

        let attachPipe = Pipe()
        attachProcess.standardOutput = attachPipe
        attachProcess.standardError = Pipe()

        do {
            try attachProcess.run()
            attachProcess.waitUntilExit()
        } catch {
            NSLog("Failed to attach disk image for FileVault check: \(error)")
            return false
        }

        guard attachProcess.terminationStatus == 0 else {
            NSLog("hdiutil attach failed for FileVault check with exit code \(attachProcess.terminationStatus)")
            return false
        }

        let attachOutput = String(data: attachPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard let deviceNode = extractDeviceNode(from: attachOutput) else {
            NSLog("Could not extract device node for FileVault check")
            return false
        }

        defer {
            // Detach the disk image
            let detachProcess = Process()
            detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detachProcess.arguments = ["detach", deviceNode]
            try? detachProcess.run()
            detachProcess.waitUntilExit()
        }

        // Check for locked volumes using the APFS list
        if let containerInfo = await findAPFSContainerUsingAPFSList(deviceNode: deviceNode) {
            return containerInfo.hasLockedVolumes
        }

        return false
    }

    public static func recommendedStrategy(for format: VBManagedDiskImage.Format) -> ResizeStrategy {
        switch format {
        case .raw:
            return .expandInPlace  // Use in-place expansion to save disk space
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
        strategy: ResizeStrategy? = nil,
        guestType: VBGuestType = .mac
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
            try await expandImageInPlace(at: url, format: format, newSize: newSize, guestType: guestType)
        }

        // After resizing the disk image, attempt to expand the partition
        // Skip for Linux VMs - Linux does not use APFS and should handle partition expansion at boot
        if guestType == .mac {
            try await expandPartitionsInDiskImage(at: url, format: format)
        } else {
            NSLog("Skipping partition expansion for non-macOS guest (type: \(guestType)) - guest OS will handle partition resize")
        }
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
    
    private static func expandImageInPlace(at url: URL, format: VBManagedDiskImage.Format, newSize: UInt64, guestType: VBGuestType = .mac) async throws {
        let parentDir = url.deletingLastPathComponent()
        let availableSpace = try await getAvailableSpace(at: parentDir)

        // Get current file size
        let currentSize = try await getCurrentImageSize(at: url, format: format)
        let additionalSpaceNeeded = newSize > currentSize ? newSize - currentSize : 0

        guard availableSpace >= additionalSpaceNeeded else {
            throw VBDiskResizeError.insufficientSpace(required: additionalSpaceNeeded, available: availableSpace)
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
            // Only adjust GPT layout for APFS partitions on macOS guests
            // Linux VMs use different partition types (ext4, etc.) and don't have APFS
            if guestType == .mac {
                try adjustGPTLayoutForRawImage(at: url, newSize: newSize)
            } else {
                NSLog("Skipping APFS GPT layout adjustment for non-macOS guest (type: \(guestType))")
            }

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
        NSLog("Partition layout for \(deviceNode):\n\(listOutput)")
        
        // First, check if we need to use diskutil apfs list to find the APFS container
        // This is needed when the partition is an APFS volume rather than a container
        // Also check if the device itself is an APFS container (common for VM disk images)
        if let apfsContainerFromList = await findAPFSContainerUsingAPFSList(deviceNode: deviceNode) {
            if apfsContainerFromList.hasLockedVolumes {
                throw VBDiskResizeError.apfsVolumesLocked(container: apfsContainerFromList.container)
            }
            let targetDescription = apfsContainerFromList.physicalStore ?? apfsContainerFromList.container
            NSLog("Found APFS container using 'diskutil apfs list': \(apfsContainerFromList.container) (store: \(targetDescription))")
            try await resizeAPFSContainer(apfsContainerFromList)
        } else if listOutput.contains("Apple_APFS_Recovery") {
            // Check if there's an Apple_APFS_Recovery partition blocking expansion
            NSLog("Detected Apple_APFS_Recovery partition - attempting recovery partition resize strategy")
            try await resizeWithRecoveryPartition(deviceNode: deviceNode, listOutput: listOutput)
        } else if let apfsContainer = findAPFSContainer(in: listOutput, deviceNode: deviceNode) {
            let targetDescription = apfsContainer.physicalStore ?? apfsContainer.container
            NSLog("Found APFS container: \(apfsContainer.container) (store: \(targetDescription))")
            try await resizeAPFSContainer(apfsContainer)
        } else if listOutput.contains("Apple_APFS") {
            // The disk might be an APFS container itself (common for VM images)
            // Try to resize it directly
            NSLog("Disk appears to have APFS partitions, attempting to resize \(deviceNode) as container")
            let cleanDevice = sanitizeDeviceIdentifier(deviceNode)
            let containerInfo = APFSContainerInfo(container: cleanDevice, physicalStore: nil, hasLockedVolumes: false)
            try await resizeAPFSContainer(containerInfo)
        } else if let hfsPartition = findHFSPartition(in: listOutput, deviceNode: deviceNode) {
            NSLog("Found HFS+ partition: \(hfsPartition)")
            try await resizeHFSPartition(hfsPartition)
        } else {
            // Fallback: try the original method
            if let partitionIdentifier = findResizablePartition(in: listOutput, deviceNode: deviceNode) {
                NSLog("Using fallback resize for partition: \(partitionIdentifier)")
                try await resizeGenericPartition(partitionIdentifier)
            } else {
                NSLog("Warning: Could not find any resizable partition on \(deviceNode)")
            }
        }
    }
    
    private static func resizeAPFSContainer(_ info: APFSContainerInfo) async throws {
        if info.hasLockedVolumes {
            throw VBDiskResizeError.apfsVolumesLocked(container: info.container)
        }

        let resizeTarget = info.physicalStore ?? info.container

        let primaryResult = runDiskutilCommand(arguments: ["apfs", "resizeContainer", resizeTarget, "0"])

        if primaryResult.status == 0 {
            NSLog("Successfully expanded APFS container target \(resizeTarget)")
        } else {
            NSLog("Warning: Failed to resize APFS container target \(resizeTarget): \(primaryResult.output)")
            if primaryResult.output.localizedCaseInsensitiveContains("locked") {
                throw VBDiskResizeError.apfsVolumesLocked(container: info.container)
            }
        }

        // When resizing using the physical store, issue a follow-up pass on the logical container to
        // encourage APFS to grow the volumes to the new ceiling. Ignore failures in this follow-up.
        if info.physicalStore != nil && info.container != resizeTarget {
            let containerTarget = info.container
            let containerResult = runDiskutilCommand(arguments: ["apfs", "resizeContainer", containerTarget, "0"])

            if containerResult.status == 0 {
                NSLog("Performed follow-up resize on APFS container \(containerTarget)")
            } else {
                NSLog("Follow-up resize on container \(containerTarget) failed (ignored): \(containerResult.output)")
                if containerResult.output.localizedCaseInsensitiveContains("locked") {
                    throw VBDiskResizeError.apfsVolumesLocked(container: info.container)
                }
            }
        }

        try await ensureAPFSContainerMaximized(info: info)
    }
    
    private static func resizeHFSPartition(_ partitionIdentifier: String) async throws {
        try await resizeGenericPartition(partitionIdentifier)
    }
    
    private static func resizeGenericPartition(_ partitionIdentifier: String) async throws {
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
            // Check if this is an APFS volume that needs container resizing
            if resizeOutput.contains("is an APFS Volume") && resizeOutput.contains("diskutil apfs resizeContainer") {
                NSLog("Partition \(partitionIdentifier) is an APFS Volume, attempting to find and resize its container")
                
                // Extract the base device (e.g., /dev/disk10 from /dev/disk10s2)
                // We need to find the last 's' followed by a number to properly extract the base device
                let baseDevice: String
                if let lastSIndex = partitionIdentifier.lastIndex(of: "s"),
                   partitionIdentifier.index(after: lastSIndex) < partitionIdentifier.endIndex,
                   partitionIdentifier[partitionIdentifier.index(after: lastSIndex)].isNumber {
                    baseDevice = String(partitionIdentifier[..<lastSIndex])
                } else {
                    baseDevice = partitionIdentifier
                }
                
                // Try to find the container using diskutil apfs list
                if let container = await findAPFSContainerUsingAPFSList(deviceNode: baseDevice) {
                    let targetDescription = container.physicalStore ?? container.container
                    NSLog("Found APFS container \(container.container) for volume \(partitionIdentifier) (store: \(targetDescription))")
                    try await resizeAPFSContainer(container)
                } else {
                    NSLog("Warning: Could not find APFS container for volume \(partitionIdentifier)")
                    // Last resort: try to resize the base device itself as it might be the container
                    let sanitizedBase = sanitizeDeviceIdentifier(baseDevice)
                    NSLog("Attempting to resize base device \(sanitizedBase) as APFS container")
                    let fallbackInfo = APFSContainerInfo(container: sanitizedBase, physicalStore: nil, hasLockedVolumes: false)
                    try await resizeAPFSContainer(fallbackInfo)
                }
            } else {
                NSLog("Warning: Failed to resize partition \(partitionIdentifier): \(resizeOutput)")
            }
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
    
    private static func findAPFSContainerUsingAPFSList(deviceNode: String) async -> APFSContainerInfo? {
        let apfsListProcess = Process()
        apfsListProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        apfsListProcess.arguments = ["apfs", "list", "-plist"]

        let apfsListPipe = Pipe()
        apfsListProcess.standardOutput = apfsListPipe
        apfsListProcess.standardError = Pipe()

        do {
            try apfsListProcess.run()
            apfsListProcess.waitUntilExit()
        } catch {
            NSLog("Failed to run 'diskutil apfs list -plist': \(error)")
            return nil
        }

        guard apfsListProcess.terminationStatus == 0 else {
            NSLog("'diskutil apfs list -plist' failed with exit code \(apfsListProcess.terminationStatus)")
            return nil
        }

        let data = apfsListPipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let containers = plist["Containers"] as? [[String: Any]]
        else {
            NSLog("Failed to parse 'diskutil apfs list -plist' output")
            return nil
        }

        let cleanDeviceNode = sanitizeDeviceIdentifier(deviceNode)
        var candidates: [(info: APFSContainerInfo, size: UInt64, isMainContainer: Bool)] = []

        for container in containers {
            guard let containerRef = container["ContainerReference"] as? String else { continue }
            let volumes = container["Volumes"] as? [[String: Any]] ?? []
            let roles = volumes.compactMap { $0["Roles"] as? [String] }.flatMap { $0 }
            let hasLockedVolumes = volumes.contains { ($0["Locked"] as? Bool) == true }

            // Detect MAIN container: has "System" or "Data" role (the boot/data container)
            let hasSystemOrData = roles.contains(where: { $0 == "System" }) || roles.contains(where: { $0 == "Data" })

            // Detect ISC container: has "xART" or "Hardware" roles (unique to Internal Shared Cache)
            let hasISCRoles = roles.contains(where: { $0 == "xART" }) || roles.contains(where: { $0 == "Hardware" })

            // The main container is the one with System/Data and NOT ISC
            let isMainContainer = hasSystemOrData && !hasISCRoles

            let physicalStores = container["PhysicalStores"] as? [[String: Any]] ?? []
            for store in physicalStores {
                guard let storeIdentifier = store["DeviceIdentifier"] as? String else { continue }
                guard storeIdentifier.hasPrefix(cleanDeviceNode) || containerRef == cleanDeviceNode else { continue }
                let size = store["Size"] as? UInt64 ?? 0
                let info = APFSContainerInfo(container: containerRef, physicalStore: storeIdentifier, hasLockedVolumes: hasLockedVolumes)
                candidates.append((info: info, size: size, isMainContainer: isMainContainer))
                NSLog("APFS candidate: container=\(containerRef), store=\(storeIdentifier), size=\(size), isMain=\(isMainContainer), hasSystemOrData=\(hasSystemOrData), hasISCRoles=\(hasISCRoles), roles=\(roles)")
            }

            if containerRef == cleanDeviceNode {
                let size = (physicalStores.first?["Size"] as? UInt64) ?? 0
                let info = APFSContainerInfo(container: containerRef, physicalStore: nil, hasLockedVolumes: hasLockedVolumes)
                candidates.append((info: info, size: size, isMainContainer: isMainContainer))
            }
        }

        guard !candidates.isEmpty else {
            NSLog("No APFS container found in 'diskutil apfs list' for device \(cleanDeviceNode)")
            return nil
        }

        // Selection priority:
        // 1. Find the MAIN container (has System/Data, not ISC) that is unlocked
        // 2. Fall back to largest unlocked container
        // 3. Fall back to any container

        let selected: (info: APFSContainerInfo, size: UInt64, isMainContainer: Bool)?

        // First priority: unlocked main container
        if let mainUnlocked = candidates.first(where: { $0.isMainContainer && !$0.info.hasLockedVolumes }) {
            selected = mainUnlocked
            NSLog("Selected unlocked main APFS container: \(mainUnlocked.info.container)")
        }
        // Second priority: any main container (even if locked)
        else if let mainAny = candidates.first(where: { $0.isMainContainer }) {
            selected = mainAny
            NSLog("Selected main APFS container (locked): \(mainAny.info.container)")
        }
        // Third priority: largest unlocked non-main container
        else if let largestUnlocked = candidates.filter({ !$0.info.hasLockedVolumes }).max(by: { $0.size < $1.size }) {
            selected = largestUnlocked
            NSLog("Selected largest unlocked APFS container: \(largestUnlocked.info.container)")
        }
        // Last resort: any container
        else {
            selected = candidates.first
            NSLog("Selected fallback APFS container: \(selected?.info.container ?? "none")")
        }

        if let selected = selected {
            NSLog("Final APFS container selection: \(selected.info.container) (store: \(selected.info.physicalStore ?? "none"), size: \(selected.size), isMain: \(selected.isMainContainer))")
        }

        return selected?.info
    }
    
    private static func findAPFSContainer(in diskutilOutput: String, deviceNode: String) -> APFSContainerInfo? {
        let lines = diskutilOutput.components(separatedBy: .newlines)
        var foundContainers: [(info: APFSContainerInfo, isMain: Bool)] = [] // (partition, containerRef, isMainContainer)
        
        // Look for APFS Container entries with their container references
        // Format: "2:                 Apple_APFS Container disk11        47.8 GB    disk8s2"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip header and empty lines
            guard !trimmed.isEmpty && !trimmed.contains("TYPE NAME") else { continue }
            
            // Look for Apple_APFS entries (but not ISC or Recovery)
            if trimmed.contains("Apple_APFS") && !trimmed.contains("Apple_APFS_Recovery") {
                let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                
                // Find partition number
                var partitionNum: String?
                var containerRef: String?
                
                for (index, component) in components.enumerated() {
                    // Get partition number (e.g., "2:" -> "2")
                    if component.hasSuffix(":") {
                        partitionNum = String(component.dropLast())
                    }
                    
                    // Look for "Container disk" pattern
                    if component == "Container" && index + 1 < components.count {
                        let nextComponent = components[index + 1]
                        if nextComponent.hasPrefix("disk") {
                            containerRef = nextComponent
                        }
                    }
                }
                
                if let partition = partitionNum {
                    let partitionDevice = sanitizeDeviceIdentifier("\(deviceNode)s\(partition)")
                    let isMainContainer = !trimmed.contains("Apple_APFS_ISC")

                    let containerIdentifier = sanitizeDeviceIdentifier(containerRef ?? partitionDevice)
                    let info = APFSContainerInfo(container: containerIdentifier, physicalStore: partitionDevice, hasLockedVolumes: false)
                    foundContainers.append((info: info, isMain: isMainContainer))

                    NSLog("Found APFS partition: \(partitionDevice) -> Container: \(containerIdentifier) (main: \(isMainContainer))")
                }
            }
        }
        
        // Prefer main containers over ISC containers
        if let mainContainer = foundContainers.first(where: { $0.isMain }) {
            NSLog("Using main APFS container: \(mainContainer.info.container)")
            return APFSContainerInfo(container: mainContainer.info.container, physicalStore: mainContainer.info.physicalStore, hasLockedVolumes: false)
        } else if let anyContainer = foundContainers.first {
            NSLog("Using fallback APFS container: \(anyContainer.info.container)")
            return APFSContainerInfo(container: anyContainer.info.container, physicalStore: anyContainer.info.physicalStore, hasLockedVolumes: false)
        }
        
        NSLog("No APFS container found in diskutil output")
        return nil
    }
    
    private static func findHFSPartition(in diskutilOutput: String, deviceNode: String) -> String? {
        let lines = diskutilOutput.components(separatedBy: .newlines)
        
        // Look for HFS+ partitions
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip header and empty lines
            guard !trimmed.isEmpty && !trimmed.contains("TYPE NAME") else { continue }
            
            // Look for Apple_HFS partition (Mac OS Extended)
            if trimmed.contains("Apple_HFS") && !trimmed.contains("Container") {
                // Extract partition number (e.g., "2:" -> "disk4s2")
                let components = trimmed.components(separatedBy: .whitespaces)
                for component in components {
                    if component.hasSuffix(":") {
                        let partitionNum = component.dropLast() // Remove ":"
                        let hfsDevice = "\(deviceNode)s\(partitionNum)"
                        NSLog("Found HFS+ partition: \(hfsDevice)")
                        return hfsDevice
                    }
                }
            }
        }
        
        NSLog("No HFS+ partition found in diskutil output")
        return nil
    }
    
    private static func resizeWithRecoveryPartition(deviceNode: String, listOutput: String) async throws {
        NSLog("Handling partition layout with Apple_APFS_Recovery partition")
        
        guard let mainContainer = findAPFSContainer(in: listOutput, deviceNode: deviceNode) else {
            NSLog("Could not find main APFS container for recovery partition resize")
            return
        }

        let mainContainerTarget = mainContainer.physicalStore ?? mainContainer.container
        NSLog("Primary APFS container for recovery handling: \(mainContainer.container) (store: \(mainContainerTarget))")

        // Check if recovery partition is blocking expansion
        let recoveryPartition = findRecoveryPartition(in: listOutput, deviceNode: deviceNode)

        if let recovery = recoveryPartition {
            NSLog("Found recovery partition: \(recovery)")
            NSLog("Recovery partition detected - attempting advanced resize strategies")
            
            // Strategy 1: Try to delete the recovery partition to allow expansion
            NSLog("Attempting to temporarily remove recovery partition for expansion")
            
            // First, we need to find the actual container reference for the recovery partition
            // The recovery partition is typically a synthesized disk, so we need to find its container
            let recoveryContainer = findRecoveryContainer(in: listOutput)
            
            if let containerToDelete = recoveryContainer {
                NSLog("Found recovery container reference: \(containerToDelete)")
                
                let deleteProcess = Process()
                deleteProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                deleteProcess.arguments = ["apfs", "deleteContainer", containerToDelete, "-force"]
                
                let deletePipe = Pipe()
                deleteProcess.standardOutput = deletePipe
                deleteProcess.standardError = deletePipe
                
                try deleteProcess.run()
                deleteProcess.waitUntilExit()
                
                let deleteOutput = String(data: deletePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                if deleteProcess.terminationStatus == 0 {
                    NSLog("Successfully removed recovery partition, attempting main container resize")
                    
                    // Now try to resize the main container
                    try await resizeAPFSContainer(mainContainer)
                    
                    NSLog("Main container resized successfully")
                    // Note: The recovery partition will be recreated by macOS when needed
                    
                    return // Exit early on success
                } else {
                    NSLog("Could not remove recovery container: \(deleteOutput)")
                    
                    // Check if it's protected by SIP
                    if deleteOutput.contains("csrutil disable") || deleteOutput.contains("Recovery Container") {
                        NSLog("Recovery partition is protected by System Integrity Protection (SIP)")
                        NSLog("The disk image has been successfully resized to provide more total space")
                        NSLog("To fully utilize the space, you can:")
                        NSLog("1. Boot the VM into Recovery Mode (Command+R during startup)")
                        NSLog("2. Use Disk Utility to manually adjust partitions")
                        NSLog("3. Or disable SIP temporarily if needed (not recommended)")
                        return // This is actually successful, just with limitations
                    }
                }
            } else {
                NSLog("Could not identify recovery container reference")
                
                // Strategy 2: Try using the limit parameter to resize up to the recovery partition
                NSLog("Attempting to resize main container up to recovery partition boundary")
                
                // Get total disk size (might be useful for debugging)
                let diskInfoProcess = Process()
                diskInfoProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                diskInfoProcess.arguments = ["info", deviceNode]
                
                let diskInfoPipe = Pipe()
                diskInfoProcess.standardOutput = diskInfoPipe
                diskInfoProcess.standardError = Pipe()
                
                try diskInfoProcess.run()
                diskInfoProcess.waitUntilExit()
                
                _ = diskInfoPipe.fileHandleForReading.readDataToEndOfFile()
                
                // Try to resize leaving space for recovery
                let resizeProcess = Process()
                resizeProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                let recoveryResizeTarget = mainContainer.physicalStore ?? mainContainer.container
                resizeProcess.arguments = ["apfs", "resizeContainer", recoveryResizeTarget, "0"]
                
                let resizePipe = Pipe()
                resizeProcess.standardOutput = resizePipe
                resizeProcess.standardError = resizePipe
                
                try resizeProcess.run()
                resizeProcess.waitUntilExit()
                
                let resizeOutput = String(data: resizePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                if resizeProcess.terminationStatus == 0 {
                    NSLog("Successfully resized APFS container")
                } else {
                    NSLog("Container resize failed: \(resizeOutput)")
                    NSLog("The disk image has been enlarged successfully")
                    NSLog("Note: The available space may be used by macOS dynamically")
                }
            }
        } else {
            NSLog("No recovery partition found, proceeding with standard resize")
            try await resizeAPFSContainer(mainContainer)
        }
    }
    
    private static func parsePartitionLayout(_ listOutput: String, deviceNode: String) -> [(number: Int, type: String, name: String, size: String)] {
        let lines = listOutput.components(separatedBy: .newlines)
        var partitions: [(number: Int, type: String, name: String, size: String)] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.contains("TYPE NAME") && trimmed.contains(":") else { continue }
            
            let components = trimmed.components(separatedBy: .whitespaces)
            if let first = components.first, first.hasSuffix(":") {
                let partitionNum = String(first.dropLast())
                if let num = Int(partitionNum), components.count >= 4 {
                    let type = components[1]
                    let name = components.count > 2 ? components[2] : ""
                    let size = components.count > 3 ? components[3] : ""
                    partitions.append((number: num, type: type, name: name, size: size))
                }
            }
        }
        
        return partitions
    }
    
    private static func findRecoveryPartition(in diskutilOutput: String, deviceNode: String) -> String? {
        let lines = diskutilOutput.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.contains("TYPE NAME") else { continue }
            
            if trimmed.contains("Apple_APFS_Recovery") || (trimmed.contains("Recovery") && trimmed.contains("Container")) {
                let components = trimmed.components(separatedBy: .whitespaces)
                for component in components {
                    if component.hasSuffix(":") {
                        let partitionNum = component.dropLast()
                        let recoveryDevice = "\(deviceNode)s\(partitionNum)"
                        NSLog("Found recovery partition: \(recoveryDevice)")
                        return recoveryDevice
                    }
                }
            }
        }
        
        return nil
    }
    
    private static func findRecoveryContainer(in diskutilOutput: String) -> String? {
        let lines = diskutilOutput.components(separatedBy: .newlines)
        
        // Look for the recovery container - it's typically shown as "Container disk6" in the output
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.contains("TYPE NAME") else { continue }
            
            if trimmed.contains("Apple_APFS_Recovery") && trimmed.contains("Container") {
                // Extract the container disk reference (e.g., "disk6" from "Container disk6")
                let components = trimmed.components(separatedBy: .whitespaces)
                
                // Look for "Container" followed by "diskX"
                for (index, component) in components.enumerated() {
                    if component == "Container" && index + 1 < components.count {
                        let nextComponent = components[index + 1]
                        if nextComponent.hasPrefix("disk") {
                            NSLog("Found recovery container: \(nextComponent)")
                            return nextComponent
                        }
                    }
                }
            }
        }
        
        NSLog("Could not find recovery container in diskutil output")
        return nil
    }
    
    private static func ensureAPFSContainerMaximized(info: APFSContainerInfo) async throws {
        if info.hasLockedVolumes {
            throw VBDiskResizeError.apfsVolumesLocked(container: info.container)
        }

        guard let details = try fetchAPFSContainerDetails(container: info.container) else {
            return
        }

        let physicalSize = details.physicalStoreSize
        let capacity = details.capacityCeiling
        let tolerance: UInt64 = 1 * 1024 * 1024 // 1 MB tolerance to account for rounding

        if physicalSize > capacity + tolerance {
            NSLog("APFS container \(info.container) ceiling (\(capacity)) is below physical store size (\(physicalSize)); nudging container")
            try await nudgeAPFSContainer(info: info, physicalSize: physicalSize)

            if let postDetails = try fetchAPFSContainerDetails(container: info.container) {
                NSLog("Post-nudge container ceiling: \(postDetails.capacityCeiling) (store: \(postDetails.physicalStoreSize))")
            }
        }
    }

    private static func fetchAPFSContainerDetails(container: String) throws -> APFSContainerDetails? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["apfs", "list", "-plist", container]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            NSLog("Failed to query APFS container \(container): \(output)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let containers = plist["Containers"] as? [[String: Any]],
            let first = containers.first,
            let capacity = first["CapacityCeiling"] as? UInt64,
            let stores = first["PhysicalStores"] as? [[String: Any]],
            let store = stores.first,
            let storeSize = store["Size"] as? UInt64
        else {
            NSLog("Could not parse APFS container details for \(container)")
            return nil
        }

        return APFSContainerDetails(capacityCeiling: capacity, physicalStoreSize: storeSize)
    }

    private static func nudgeAPFSContainer(info: APFSContainerInfo, physicalSize: UInt64) async throws {
        let alignment: UInt64 = 4096
        let shrinkDelta: UInt64 = 32 * 1024 * 1024 // 32 MB nudge to ensure actual size change
        let resizeTarget = info.physicalStore ?? info.container

        guard physicalSize > alignment else { return }

        let tentativeShrink = physicalSize > shrinkDelta ? physicalSize - shrinkDelta : physicalSize - alignment
        let alignedShrink = max((tentativeShrink / alignment) * alignment, alignment)

        let shrinkArg = "\(alignedShrink)B"
        let shrinkResult = runDiskutilCommand(arguments: ["apfs", "resizeContainer", resizeTarget, shrinkArg])

        if shrinkResult.status != 0 {
            NSLog("APFS shrink nudge for \(resizeTarget) failed: \(shrinkResult.output)")
            if shrinkResult.output.localizedCaseInsensitiveContains("locked") {
                throw VBDiskResizeError.apfsVolumesLocked(container: info.container)
            }
        }

        let growResult = runDiskutilCommand(arguments: ["apfs", "resizeContainer", resizeTarget, "0"])
        if growResult.status != 0 {
            NSLog("APFS grow after nudge for \(resizeTarget) failed: \(growResult.output)")
            if growResult.output.localizedCaseInsensitiveContains("locked") {
                throw VBDiskResizeError.apfsVolumesLocked(container: info.container)
            }
        }
    }

    private static func runDiskutilCommand(arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("Failed to run diskutil \(arguments.joined(separator: " ")): \(error)")
            return (-1, "\(error)")
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private static func adjustGPTLayoutForRawImage(at url: URL, newSize: UInt64) throws {
        try GPTLayoutAdjuster(imageURL: url, newSize: newSize).perform()
    }

    private struct GPTLayoutAdjuster {
        let imageURL: URL
        let newSize: UInt64

        private let sectorSize: UInt64 = 512
        private let mainContainerGUID = UUID(uuidString: "7C3457EF-0000-11AA-AA11-00306543ECAC")!
        private let recoveryGUID = UUID(uuidString: "52637672-7900-11AA-AA11-00306543ECAC")!

        func perform() throws {
            guard newSize % sectorSize == 0 else {
                throw VBDiskResizeError.systemCommandFailed("New disk size must be 512-byte aligned", -1)
            }

            let fileHandle = try FileHandle(forUpdating: imageURL)
            defer { try? fileHandle.close() }

            let headerOffset = sectorSize
            try fileHandle.vbSeek(to: headerOffset)
            let headerData = try readExactly(fileHandle: fileHandle, length: Int(sectorSize))

            var header = GPTHeader(data: headerData)
            let entriesOffset = UInt64(header.partitionEntriesLBA) * sectorSize
            let entriesLength = Int(header.numberOfEntries) * Int(header.entrySize)

            try fileHandle.vbSeek(to: entriesOffset)
            var entries = try readExactly(fileHandle: fileHandle, length: entriesLength)

            guard
                let mainIndex = findPartitionIndex(in: entries, guid: mainContainerGUID, entrySize: Int(header.entrySize), preferLargest: true),
                let recoveryIndex = findPartitionIndex(in: entries, guid: recoveryGUID, entrySize: Int(header.entrySize), preferLargest: false)
            else {
                throw NSError(domain: "VBDiskResizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not locate APFS partitions in GPT"])
            }

            let mainLast = readUInt64LittleEndian(from: entries, offset: mainIndex * Int(header.entrySize) + 40)
            let recoveryFirst = readUInt64LittleEndian(from: entries, offset: recoveryIndex * Int(header.entrySize) + 32)
            let recoveryLast = readUInt64LittleEndian(from: entries, offset: recoveryIndex * Int(header.entrySize) + 40)

            let recoveryLength = recoveryLast - recoveryFirst + 1

            let totalSectors = newSize / sectorSize
            let newBackupLBA = totalSectors - 1
            let backupEntriesLBA = newBackupLBA - 32
            var newLastUsable = backupEntriesLBA - 8
            var newRecoveryFirst = newLastUsable - (recoveryLength - 1)

            let alignment: UInt64 = 8
            let remainder = newRecoveryFirst % alignment
            if remainder != 0 {
                newRecoveryFirst -= remainder
                newLastUsable = newRecoveryFirst + recoveryLength - 1
            }

            let newMainLast = newRecoveryFirst - 1

            guard newMainLast > mainLast else {
                // Nothing to do if the main container already occupies the space
                return
            }

            try copySectors(
                fileHandle: fileHandle,
                from: recoveryFirst,
                to: newRecoveryFirst,
                count: recoveryLength,
                sectorSize: sectorSize
            )

            try zeroSectors(
                fileHandle: fileHandle,
                start: recoveryFirst,
                count: recoveryLength,
                sectorSize: sectorSize
            )

            writeUInt64LittleEndian(
                &entries,
                offset: mainIndex * Int(header.entrySize) + 40,
                value: newMainLast
            )

            writeUInt64LittleEndian(
                &entries,
                offset: recoveryIndex * Int(header.entrySize) + 32,
                value: newRecoveryFirst
            )

            writeUInt64LittleEndian(
                &entries,
                offset: recoveryIndex * Int(header.entrySize) + 40,
                value: newLastUsable
            )

            header.backupLBA = newBackupLBA
            header.lastUsableLBA = newLastUsable
            header.partitionEntriesCRC32 = crc32(of: entries)

            try fileHandle.vbSeek(to: entriesOffset)
            try fileHandle.vbWriteAll(entries)

            let primaryHeaderData = header.serialized(sectorSize: sectorSize, isBackup: false)
            try fileHandle.vbSeek(to: headerOffset)
            try fileHandle.vbWriteAll(primaryHeaderData)

            let backupEntriesOffset = backupEntriesLBA * sectorSize
            try fileHandle.vbSeek(to: backupEntriesOffset)
            try fileHandle.vbWriteAll(entries)

            let backupHeaderData = header.serialized(sectorSize: sectorSize, isBackup: true)
            try fileHandle.vbSeek(to: newBackupLBA * sectorSize)
            try fileHandle.vbWriteAll(backupHeaderData)

            try fileHandle.vbSynchronize()
        }

        private func readExactly(fileHandle: FileHandle, length: Int) throws -> Data {
            let data = try fileHandle.vbRead(upToCount: length) ?? Data()
            guard data.count == length else {
                throw NSError(domain: "VBDiskResizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to read expected GPT data"])
            }
            return data
        }

        private func findPartitionIndex(in entries: Data, guid: UUID, entrySize: Int, preferLargest: Bool) -> Int? {
            var bestIndex: Int?
            var bestLength: UInt64 = 0

            for index in 0..<(entries.count / entrySize) {
                let base = index * entrySize
                let typeData = entries.subdata(in: base..<(base + 16))
                guard let entryGUID = uuidFromGPTBytes(typeData), entryGUID == guid else {
                    continue
                }

                if !preferLargest {
                    return index
                }

                let first = readUInt64LittleEndian(from: entries, offset: base + 32)
                let last = readUInt64LittleEndian(from: entries, offset: base + 40)
                let length = last >= first ? last - first : 0
                if length > bestLength {
                    bestLength = length
                    bestIndex = index
                }
            }

            return preferLargest ? bestIndex : nil
        }

        private func copySectors(fileHandle: FileHandle, from: UInt64, to: UInt64, count: UInt64, sectorSize: UInt64) throws {
            let bufferSize: UInt64 = 4 * 1024 * 1024
            var remaining = count * sectorSize
            var readOffset = from * sectorSize
            var writeOffset = to * sectorSize

            while remaining > 0 {
                let chunk = Int(min(bufferSize, remaining))
                try fileHandle.vbSeek(to: readOffset)
                let data = try readExactly(fileHandle: fileHandle, length: chunk)

                try fileHandle.vbSeek(to: writeOffset)
                try fileHandle.vbWriteAll(data)

                remaining -= UInt64(chunk)
                readOffset += UInt64(chunk)
                writeOffset += UInt64(chunk)
            }
        }

        private func zeroSectors(fileHandle: FileHandle, start: UInt64, count: UInt64, sectorSize: UInt64) throws {
            let bufferSize: UInt64 = 4 * 1024 * 1024
            var remaining = count * sectorSize
            var offset = start * sectorSize
            let zeroChunk = Data(count: Int(min(bufferSize, remaining)))

            while remaining > 0 {
                let chunk = Int(min(UInt64(zeroChunk.count), remaining))
                try fileHandle.vbSeek(to: offset)
                try fileHandle.vbWriteAll(zeroChunk.prefix(chunk))

                remaining -= UInt64(chunk)
                offset += UInt64(chunk)
            }
        }
    }

    private struct GPTHeader {
        var signature: UInt64
        var revision: UInt32
        var headerSize: UInt32
        var headerCRC32: UInt32
        var reserved: UInt32
        var currentLBA: UInt64
        var backupLBA: UInt64
        var firstUsableLBA: UInt64
        var lastUsableLBA: UInt64
        var diskGUID: Data
        var partitionEntriesLBA: UInt64
        var numberOfEntries: UInt32
        var entrySize: UInt32
        var partitionEntriesCRC32: UInt32

        init(data: Data) {
            signature = readUInt64LittleEndian(from: data, offset: 0)
            revision = readUInt32LittleEndian(from: data, offset: 8)
            headerSize = readUInt32LittleEndian(from: data, offset: 12)
            headerCRC32 = readUInt32LittleEndian(from: data, offset: 16)
            reserved = readUInt32LittleEndian(from: data, offset: 20)
            currentLBA = readUInt64LittleEndian(from: data, offset: 24)
            backupLBA = readUInt64LittleEndian(from: data, offset: 32)
            firstUsableLBA = readUInt64LittleEndian(from: data, offset: 40)
            lastUsableLBA = readUInt64LittleEndian(from: data, offset: 48)
            diskGUID = data.subdata(in: 56..<72)
            partitionEntriesLBA = readUInt64LittleEndian(from: data, offset: 72)
            numberOfEntries = readUInt32LittleEndian(from: data, offset: 80)
            entrySize = readUInt32LittleEndian(from: data, offset: 84)
            partitionEntriesCRC32 = readUInt32LittleEndian(from: data, offset: 88)
        }

        func serialized(sectorSize: UInt64, isBackup: Bool) -> Data {
            var data = Data(count: Int(sectorSize))
            writeUInt64LittleEndian(&data, offset: 0, value: signature)
            writeUInt32LittleEndian(&data, offset: 8, value: revision)
            writeUInt32LittleEndian(&data, offset: 12, value: headerSize)
            writeUInt32LittleEndian(&data, offset: 16, value: 0) // placeholder for CRC
            writeUInt32LittleEndian(&data, offset: 20, value: reserved)
            let current = isBackup ? backupLBA : currentLBA
            let backup = isBackup ? currentLBA : backupLBA
            writeUInt64LittleEndian(&data, offset: 24, value: current)
            writeUInt64LittleEndian(&data, offset: 32, value: backup)
            writeUInt64LittleEndian(&data, offset: 40, value: firstUsableLBA)
            writeUInt64LittleEndian(&data, offset: 48, value: lastUsableLBA)
            data.replaceSubrange(56..<72, with: diskGUID)
            let entriesLBA = isBackup ? (backupLBA - 32) : partitionEntriesLBA
            writeUInt64LittleEndian(&data, offset: 72, value: entriesLBA)
            writeUInt32LittleEndian(&data, offset: 80, value: numberOfEntries)
            writeUInt32LittleEndian(&data, offset: 84, value: entrySize)
            writeUInt32LittleEndian(&data, offset: 88, value: partitionEntriesCRC32)

            let crc = crc32(of: data.prefix(Int(headerSize)))
            writeUInt32LittleEndian(&data, offset: 16, value: crc)
            return data
        }
    }

    private static func crc32(of data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer -> UInt32 in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return UInt32(zlib.crc32(0, base, uInt(buffer.count)))
        }
    }

    private static func uuidFromGPTBytes(_ data: Data) -> UUID? {
        guard data.count == 16 else { return nil }
        let a = readUInt32LittleEndian(from: data, offset: 0)
        let b = readUInt16LittleEndian(from: data, offset: 4)
        let c = readUInt16LittleEndian(from: data, offset: 6)
        let tail = Array(data[8..<16])
        let uuidString = String(
            format: "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            a, b, c,
            tail[0], tail[1],
            tail[2], tail[3],
            tail[4], tail[5], tail[6], tail[7]
        )
        return UUID(uuidString: uuidString)
    }

    private static func readUInt64LittleEndian(from data: Data, offset: Int) -> UInt64 {
        let range = offset..<(offset + 8)
        return data.subdata(in: range).withUnsafeBytes { $0.load(as: UInt64.self) }.littleEndian
    }

    private static func readUInt32LittleEndian(from data: Data, offset: Int) -> UInt32 {
        let range = offset..<(offset + 4)
        return data.subdata(in: range).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    }

    private static func readUInt16LittleEndian(from data: Data, offset: Int) -> UInt16 {
        let range = offset..<(offset + 2)
        return data.subdata(in: range).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    }

    private static func writeUInt64LittleEndian(_ data: inout Data, offset: Int, value: UInt64) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes in
            data.replaceSubrange(offset..<(offset + 8), with: bytes)
        }
    }

    private static func writeUInt32LittleEndian(_ data: inout Data, offset: Int, value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes in
            data.replaceSubrange(offset..<(offset + 4), with: bytes)
        }
    }

    private static func writeUInt16LittleEndian(_ data: inout Data, offset: Int, value: UInt16) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes in
            data.replaceSubrange(offset..<(offset + 2), with: bytes)
        }
    }

}
