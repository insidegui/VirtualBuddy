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
        case .raw, .dmg, .sparseimage:
            return true
        case .asif:
            return false
        }
    }
    
    public static func recommendedStrategy(for format: VBManagedDiskImage.Format) -> ResizeStrategy {
        switch format {
        case .raw:
            return .createLargerImage
        case .dmg, .sparseimage:
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
    }
    
    private static func getCurrentImageSize(at url: URL, format: VBManagedDiskImage.Format) async throws -> UInt64 {
        switch format {
        case .raw:
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? UInt64 ?? 0
            
        case .dmg, .sparseimage:
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
                try await createRawImage(at: tempURL, size: newSize)
                
                let sourceFile = try FileHandle(forReadingFrom: backupURL)
                let destFile = try FileHandle(forWritingTo: tempURL)
                defer {
                    sourceFile.closeFile()
                    destFile.closeFile()
                }
                
                let bufferSize = 1024 * 1024
                while true {
                    let data = sourceFile.readData(ofLength: bufferSize)
                    if data.isEmpty { break }
                    destFile.write(data)
                }
                
            case .dmg, .sparseimage:
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
        case .dmg, .sparseimage:
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
        let fileHandle = try FileHandle(forWritingTo: url.appendingPathExtension("tmp"))
        defer { fileHandle.closeFile() }
        
        let result = ftruncate(fileHandle.fileDescriptor, Int64(size))
        guard result == 0 else {
            throw VBDiskResizeError.systemCommandFailed("ftruncate", result)
        }
        
        try FileManager.default.moveItem(at: url.appendingPathExtension("tmp"), to: url)
    }
    
    private static func createExpandedDMGImage(from sourceURL: URL, to destURL: URL, newSize: UInt64, format: VBManagedDiskImage.Format) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        
        let formatArg: String
        switch format {
        case .dmg:
            formatArg = "UDRW"
        case .sparseimage:
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
}