//
//  VBDiskResizer.swift
//  VirtualCore
//
//  Created by VirtualBuddy on 22/08/25.
//

import Darwin
import Foundation
import OSLog
import zlib

public enum VBDiskResizeError: LocalizedError {
    case diskImageNotFound(URL)
    case unsupportedImageFormat(VBManagedDiskImage.Format)
    case cannotShrinkDisk
    case systemCommandFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .diskImageNotFound(let url):
            return "Disk image not found at path: \(url.path)"
        case .unsupportedImageFormat(let format):
            return "Resizing is not supported for \(format.displayName) format"
        case .cannotShrinkDisk:
            return "Cannot shrink disk image. Only expansion is supported for safety reasons."
        case .systemCommandFailed(let command, let exitCode):
            return "System command '\(command)' failed with exit code \(exitCode)"
        }
    }
}

/// Expands managed disk images in place.
///
/// This only grows the disk image (and, for raw images, rewrites the GPT so the added
/// space is usable). Expanding the partition/APFS container into the new space is left
/// to the guest OS, where it works regardless of FileVault (e.g. running
/// `diskutil apfs resizeContainer disk0s2 0` in a macOS guest).
public struct VBDiskResizer {
    private static let logger = Logger(for: VBDiskResizer.self)

    public static func canResizeFormat(_ format: VBManagedDiskImage.Format) -> Bool {
        switch format {
        case .raw, .sparse:
            return true
        case .dmg, .asif:
            return false
        }
    }

    public static func resizeDiskImage(
        at url: URL,
        format: VBManagedDiskImage.Format,
        newSize: UInt64
    ) async throws {
        guard canResizeFormat(format) else {
            throw VBDiskResizeError.unsupportedImageFormat(format)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VBDiskResizeError.diskImageNotFound(url)
        }

        let currentSize = try await currentImageSize(at: url, format: format)
        guard newSize >= currentSize else {
            throw VBDiskResizeError.cannotShrinkDisk
        }

        switch format {
        case .sparse:
            guard newSize > currentSize else { return }
            let result = run("/usr/bin/hdiutil", ["resize", "-size", "\(newSize / 512)s", url.path])
            guard result.status == 0 else {
                throw VBDiskResizeError.systemCommandFailed("hdiutil resize: \(result.outputString)", result.status)
            }

        case .raw:
            let imageURL = url.resolvingSymlinksInPath()
            let temporaryURL = imageURL.deletingLastPathComponent()
                .appendingPathComponent(".\(imageURL.lastPathComponent).resize-\(UUID().uuidString)")
            var replacedOriginal = false
            defer {
                if !replacedOriginal {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }
            }

            guard copyfile(
                imageURL.path,
                temporaryURL.path,
                nil,
                copyfile_flags_t(COPYFILE_CLONE | COPYFILE_ACL | COPYFILE_DATA_SPARSE)
            ) == 0 else {
                throw VBDiskResizeError.systemCommandFailed("copyfile", errno)
            }

            do {
                let fileHandle = try FileHandle(forWritingTo: temporaryURL)
                defer { try? fileHandle.close() }

                if newSize > currentSize {
                    guard ftruncate(fileHandle.fileDescriptor, Int64(newSize)) == 0 else {
                        throw VBDiskResizeError.systemCommandFailed("ftruncate", errno)
                    }
                }

                try fileHandle.synchronize()
            }

            try GPTLayoutAdjuster(imageURL: temporaryURL, newSize: newSize).perform()

            guard rename(temporaryURL.path, imageURL.path) == 0 else {
                throw VBDiskResizeError.systemCommandFailed("rename", errno)
            }
            replacedOriginal = true

        case .dmg, .asif:
            throw VBDiskResizeError.unsupportedImageFormat(format)
        }
    }

    static func currentImageSize(at url: URL, format: VBManagedDiskImage.Format) async throws -> UInt64 {
        switch format {
        case .raw:
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? UInt64 ?? 0

        case .sparse:
            let result = run("/usr/bin/hdiutil", ["imageinfo", "-plist", url.path])
            guard result.status == 0 else {
                throw VBDiskResizeError.systemCommandFailed("hdiutil imageinfo", result.status)
            }

            guard let plist = try PropertyListSerialization.propertyList(from: result.output, options: [], format: nil) as? [String: Any],
                  let size = plist["Total Bytes"] as? UInt64 else {
                throw VBDiskResizeError.systemCommandFailed("hdiutil imageinfo", -1)
            }

            return size

        case .dmg, .asif:
            throw VBDiskResizeError.unsupportedImageFormat(format)
        }
    }

    private static func run(_ executablePath: String, _ arguments: [String]) -> (status: Int32, output: Data, outputString: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Failed to run \(executablePath, privacy: .public): \(error, privacy: .public)")
            return (-1, Data(), "\(error)")
        }

        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, output, String(decoding: output, as: UTF8.self))
    }

    /// Rewrites the GPT of a raw image after the backing file has grown: moves the backup GPT
    /// structures to the new end of the disk and relocates the recovery partition so the main
    /// APFS container's entry can be extended into the added space.
    ///
    /// If the image doesn't contain the expected macOS layout (main APFS container followed by
    /// a recovery partition), this is a no-op: the guest OS can claim the space by itself.
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
            try fileHandle.seek(toOffset: headerOffset)
            let headerData = try readExactly(fileHandle: fileHandle, length: Int(sectorSize))

            var header = GPTHeader(data: headerData)
            let (entriesOffset, entriesOffsetOverflow) = header.partitionEntriesLBA.multipliedReportingOverflow(by: sectorSize)
            let (entriesLength, entriesLengthOverflow) = UInt64(header.numberOfEntries).multipliedReportingOverflow(by: UInt64(header.entrySize))
            let (entriesEnd, entriesEndOverflow) = entriesOffset.addingReportingOverflow(entriesLength)
            let (firstUsableOffset, firstUsableOffsetOverflow) = header.firstUsableLBA.multipliedReportingOverflow(by: sectorSize)
            let totalSectors = newSize / sectorSize
            guard
                header.signature == 0x5452_4150_2049_4645,
                header.headerSize >= 92,
                header.headerSize <= sectorSize,
                header.currentLBA == 1,
                header.entrySize >= 128,
                header.entrySize.isMultiple(of: 8),
                header.numberOfEntries > 0,
                !entriesOffsetOverflow,
                !entriesLengthOverflow,
                !entriesEndOverflow,
                !firstUsableOffsetOverflow,
                entriesLength <= 32 * sectorSize,
                header.partitionEntriesLBA >= 2,
                header.firstUsableLBA <= header.lastUsableLBA,
                header.lastUsableLBA < header.backupLBA,
                header.backupLBA < totalSectors,
                entriesEnd <= firstUsableOffset,
                let entriesLengthInt = Int(exactly: entriesLength)
            else {
                logger.debug("No valid GPT header; leaving partition table for the guest to adjust")
                return
            }

            var headerForCRC = Data(headerData.prefix(Int(header.headerSize)))
            writeUInt32LittleEndian(&headerForCRC, offset: 16, value: 0)
            guard crc32(of: headerForCRC) == header.headerCRC32 else {
                logger.debug("GPT header checksum is invalid; leaving partition table for the guest to adjust")
                return
            }

            try fileHandle.seek(toOffset: entriesOffset)
            var entries = try readExactly(fileHandle: fileHandle, length: entriesLengthInt)
            guard crc32(of: entries) == header.partitionEntriesCRC32 else {
                logger.debug("GPT partition table checksum is invalid; leaving partition table for the guest to adjust")
                return
            }

            guard
                let mainIndex = findPartitionIndex(in: entries, guid: mainContainerGUID, entrySize: Int(header.entrySize), preferLargest: true),
                let recoveryIndex = findPartitionIndex(in: entries, guid: recoveryGUID, entrySize: Int(header.entrySize), preferLargest: false)
            else {
                logger.debug("No macOS APFS + recovery layout in GPT; leaving partition table for the guest to adjust")
                return
            }

            let mainFirst = readUInt64LittleEndian(from: entries, offset: mainIndex * Int(header.entrySize) + 32)
            let mainLast = readUInt64LittleEndian(from: entries, offset: mainIndex * Int(header.entrySize) + 40)
            let recoveryFirst = readUInt64LittleEndian(from: entries, offset: recoveryIndex * Int(header.entrySize) + 32)
            let recoveryLast = readUInt64LittleEndian(from: entries, offset: recoveryIndex * Int(header.entrySize) + 40)

            guard
                mainFirst >= header.firstUsableLBA,
                mainFirst <= mainLast,
                mainLast < recoveryFirst,
                recoveryFirst <= recoveryLast,
                recoveryLast == header.lastUsableLBA
            else {
                logger.debug("Unexpected macOS GPT geometry; leaving partition table for the guest to adjust")
                return
            }

            let recoveryLength = recoveryLast - recoveryFirst + 1

            guard totalSectors > 41 else {
                logger.debug("Disk is too small for GPT relocation; leaving partition table for the guest to adjust")
                return
            }
            let newBackupLBA = totalSectors - 1
            let backupEntriesLBA = newBackupLBA - 32
            var newLastUsable = backupEntriesLBA - 8
            guard newLastUsable >= recoveryLength - 1 else {
                logger.debug("Disk has no room for the recovery partition; leaving partition table for the guest to adjust")
                return
            }
            var newRecoveryFirst = newLastUsable - (recoveryLength - 1)

            let alignment: UInt64 = 8
            let remainder = newRecoveryFirst % alignment
            if remainder != 0 {
                newRecoveryFirst -= remainder
                newLastUsable = newRecoveryFirst + recoveryLength - 1
            }

            let newMainLast = newRecoveryFirst - 1

            guard newRecoveryFirst > recoveryFirst, newMainLast > mainLast else {
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

            let backupEntriesOffset = backupEntriesLBA * sectorSize
            try fileHandle.seek(toOffset: backupEntriesOffset)
            try fileHandle.write(contentsOf: entries)

            let backupHeaderData = header.serialized(sectorSize: sectorSize, isBackup: true)
            try fileHandle.seek(toOffset: newBackupLBA * sectorSize)
            try fileHandle.write(contentsOf: backupHeaderData)

            try fileHandle.seek(toOffset: entriesOffset)
            try fileHandle.write(contentsOf: entries)

            let primaryHeaderData = header.serialized(sectorSize: sectorSize, isBackup: false)
            try fileHandle.seek(toOffset: headerOffset)
            try fileHandle.write(contentsOf: primaryHeaderData)

            try fileHandle.synchronize()

            try zeroSectors(
                fileHandle: fileHandle,
                start: recoveryFirst,
                count: min(recoveryLength, newRecoveryFirst - recoveryFirst),
                sectorSize: sectorSize
            )

            try fileHandle.synchronize()
        }

        private func readExactly(fileHandle: FileHandle, length: Int) throws -> Data {
            let data = try fileHandle.read(upToCount: length) ?? Data()
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
            let sourceOffset = from * sectorSize
            let destinationOffset = to * sectorSize
            let copyBackwards = destinationOffset > sourceOffset && destinationOffset < sourceOffset + remaining

            while remaining > 0 {
                let chunk = Int(min(bufferSize, remaining))
                let offset = copyBackwards ? remaining - UInt64(chunk) : count * sectorSize - remaining
                let readOffset = sourceOffset + offset
                let writeOffset = destinationOffset + offset
                try fileHandle.seek(toOffset: readOffset)
                let data = try readExactly(fileHandle: fileHandle, length: chunk)

                try fileHandle.seek(toOffset: writeOffset)
                try fileHandle.write(contentsOf: data)

                remaining -= UInt64(chunk)
            }
        }

        private func zeroSectors(fileHandle: FileHandle, start: UInt64, count: UInt64, sectorSize: UInt64) throws {
            let bufferSize: UInt64 = 4 * 1024 * 1024
            var remaining = count * sectorSize
            var offset = start * sectorSize
            let zeroChunk = Data(count: Int(min(bufferSize, remaining)))

            while remaining > 0 {
                let chunk = Int(min(UInt64(zeroChunk.count), remaining))
                try fileHandle.seek(toOffset: offset)
                try fileHandle.write(contentsOf: zeroChunk.prefix(chunk))

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
